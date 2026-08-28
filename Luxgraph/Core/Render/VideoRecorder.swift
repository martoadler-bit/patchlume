import AVFoundation
import CoreVideo
import Metal
import Photos

/// Records the live render to an H.264 `.mov` file, then hands back a URL
/// to share/save. Deliberately video-only for v1 (no audio track) — the
/// app's audio source can be Mic, a file, or a synthetic Sim pulse with no
/// real audio at all, and mixing/syncing an audio track in correctly is
/// real additional work; a silent export is still exactly what most reel
/// workflows want (add music in the platform's own editor afterward).
/// Records at `RenderEngine.recordingResolution` (the fixed working-buffer
/// size every node already renders at) — not a separately configurable
/// export resolution, to avoid re-architecting the render pipeline's fixed
/// texture sizing for v1.
@MainActor
final class VideoRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    /// Set once a finished recording is ready to share; `ContentView`
    /// presents a `ShareLink` for it and the caller clears it after.
    @Published var lastExportURL: URL?

    /// Called once per capture tick while recording — `RenderEngine` sets
    /// this (indirectly, via `GraphViewModel`) so the recorder can ask for
    /// a frame without needing to know anything about the render engine
    /// itself.
    var onNeedsFrame: (() -> Void)?

    private let device: MTLDevice
    private var textureCache: CVMetalTextureCache?

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var captureTimer: Timer?
    private var recordingStartHostTime: CFTimeInterval?
    private var elapsedTimer: Timer?

    init(device: MTLDevice) {
        self.device = device
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    func startRecording(size: CGSize) {
        guard !isRecording else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Luxgraph-\(UUID().uuidString).mov")

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)

        guard writer.canAdd(input) else { return }
        writer.add(input)
        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: .zero)

        assetWriter = writer
        videoInput = input
        pixelBufferAdaptor = adaptor
        recordingStartHostTime = nil
        elapsedSeconds = 0
        isRecording = true

        // 30fps capture — plenty for a live-visual export, and half the
        // per-frame Metal work of matching the 60fps preview loop.
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onNeedsFrame?() }
        }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickElapsed() }
        }
    }

    private func tickElapsed() {
        guard let start = recordingStartHostTime else { return }
        elapsedSeconds = CACurrentMediaTime() - start
    }

    /// Called by `RenderEngine.captureFrameForRecording()` with the current
    /// frame's composited texture and the command buffer it was rendered
    /// into (still uncommitted) — the blit copy into the pixel buffer is
    /// encoded onto that same buffer, and the actual append to the asset
    /// writer happens once the GPU work finishes.
    func appendFrame(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard isRecording, let adaptor = pixelBufferAdaptor, let pool = adaptor.pixelBufferPool,
              videoInput?.isReadyForMoreMediaData == true else { return }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let pixelBuffer, let destTexture = makeTexture(from: pixelBuffer),
              destTexture.width == texture.width, destTexture.height == texture.height else { return }

        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                   sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                   sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                   to: destTexture, destinationSlice: 0, destinationLevel: 0,
                   destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()

        if recordingStartHostTime == nil {
            recordingStartHostTime = CACurrentMediaTime()
        }
        let seconds = CACurrentMediaTime() - (recordingStartHostTime ?? CACurrentMediaTime())
        let pts = CMTime(seconds: seconds, preferredTimescale: 600)

        commandBuffer.addCompletedHandler { [weak self] _ in
            Task { @MainActor in
                self?.pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: pts)
            }
        }
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    /// Stops capture and finishes writing the file, returning its URL on
    /// success (also published as `lastExportURL`).
    func stopRecording() async -> URL? {
        guard isRecording, let writer = assetWriter else { return nil }
        isRecording = false
        captureTimer?.invalidate()
        captureTimer = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil

        videoInput?.markAsFinished()
        await writer.finishWriting()

        let url = writer.outputURL
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        recordingStartHostTime = nil

        guard writer.status == .completed else { return nil }
        lastExportURL = url
        return url
    }

    enum SaveToPhotosResult {
        case saved
        case denied
        case failed
    }

    /// Saves an exported recording straight into the user's Photos library
    /// — separate from the `ShareLink`-driven share sheet (which already
    /// offers "Save Video" among its targets), for a one-tap path that
    /// doesn't require picking through the share sheet's app list.
    /// `.addOnly` authorization is enough (never reads the existing library),
    /// matching `NSPhotoLibraryAddUsageDescription` in Info.plist.
    func saveToPhotos(url: URL) async -> SaveToPhotosResult {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
            }
            return .saved
        } catch {
            return .failed
        }
    }
}
