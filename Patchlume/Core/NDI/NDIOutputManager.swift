import Combine
import CoreVideo
import Metal

/// Streams the live composited output over the local network as an NDI
/// source — the same "grab the final texture each frame" role
/// `VideoRecorder` plays for file export, just handed to `NDISender`
/// (Core/NDI/NDIWrapper.mm) instead of an `AVAssetWriter`. Owns its own
/// fixed-rate timer exactly like `VideoRecorder`'s `captureTimer`, so NDI
/// output works whether or not a recording is also in progress —
/// `RenderEngine.captureFrameForRecording()` feeds both consumers from the
/// same single render pass rather than rendering the graph twice.
@MainActor
final class NDIOutputManager: ObservableObject {
    @Published private(set) var isActive = false

    /// Mirrors `VideoRecorder.onNeedsFrame` — `GraphViewModel` wires this
    /// to `renderEngine.captureFrameForRecording()`.
    var onNeedsFrame: (() -> Void)?

    private let device: MTLDevice
    private let sender = NDISender()
    private var textureCache: CVMetalTextureCache?
    private var pixelBufferPool: CVPixelBufferPool?
    private var captureTimer: Timer?

    init(device: MTLDevice) {
        self.device = device
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    func start(size: CGSize) {
        guard !isActive else { return }
        guard sender.start(withName: "Patchlume") else { return }
        setupPool(size: size)
        isActive = true
        // 30fps — same cadence `VideoRecorder` uses; NDI's own network
        // path is easily the bottleneck long before this is.
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onNeedsFrame?() }
        }
    }

    func stop() {
        guard isActive else { return }
        captureTimer?.invalidate()
        captureTimer = nil
        sender.stop()
        pixelBufferPool = nil
        isActive = false
    }

    private func setupPool(size: CGSize) {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pixelBufferPool)
    }

    /// Called by `RenderEngine.captureFrameForRecording()` with the current
    /// frame's composited texture and the (still uncommitted) command
    /// buffer it was rendered into — same blit-into-a-pooled-pixel-buffer
    /// pattern `VideoRecorder.appendFrame` uses, just handing the result to
    /// `NDISender` instead of an asset writer once the GPU work finishes.
    func appendFrame(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard isActive, let pool = pixelBufferPool else { return }

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

        commandBuffer.addCompletedHandler { [weak self] _ in
            Task { @MainActor in
                self?.sender.sendFrame(with: pixelBuffer)
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
}
