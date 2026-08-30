import Combine
import CoreVideo
import Metal

/// Receives another device's NDI broadcast — a second phone running the
/// free "NDI Camera" app, another Patchlume, OBS, Resolume — as a live
/// texture for the "ndiSource" generator node. The receive-side
/// counterpart to `NDIOutputManager`; a single global engine, same as
/// `CameraCaptureEngine`, so only one NDI source is connected at a time.
///
/// NDI's receive API is a blocking poll (`captureNextFrameTimeoutMs:`),
/// not a delegate callback like AVFoundation's capture pipeline — so
/// unlike `CameraCaptureEngine`, this drives its own while-loop on a
/// background queue rather than reacting to pushed frames.
final class NDISourceEngine: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var availableSources: [String] = []
    @Published private(set) var currentSourceName: String?

    private let device: MTLDevice
    private let receiver = NDIReceiver()
    private var textureCache: CVMetalTextureCache?
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero
    private let queue = DispatchQueue(label: "com.dlrk.patchlume.ndireceive")
    private var isRunning = false

    // Same lock-protected snapshot pattern as `CameraCaptureEngine`'s
    // `_latestTexture` — written from the poll loop (background queue),
    // read from the render thread.
    private var lock = os_unfair_lock()
    private var _latestTexture: MTLTexture?

    init(device: MTLDevice) {
        self.device = device
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    var latestTexture: MTLTexture? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _latestTexture
    }

    /// Scans the local network briefly and publishes whatever NDI sources
    /// it finds — call before showing a source picker, and again if the
    /// list looks stale (a source that just started broadcasting won't
    /// appear until the next scan).
    func refreshSources() {
        queue.async { [weak self] in
            guard let self else { return }
            let names = self.receiver.discoverSourceNames()
            DispatchQueue.main.async { self.availableSources = names }
        }
    }

    func connect(toSourceNamed name: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let ok = self.receiver.connect(toSourceNamed: name)
            DispatchQueue.main.async {
                self.currentSourceName = ok ? name : nil
                self.isConnected = ok
            }
            guard ok else { return }
            self.isRunning = true
            self.pollLoop()
        }
    }

    func disconnect() {
        isRunning = false
        queue.async { [weak self] in self?.receiver.disconnect() }
        currentSourceName = nil
        isConnected = false
        os_unfair_lock_lock(&lock)
        _latestTexture = nil
        os_unfair_lock_unlock(&lock)
    }

    /// Runs on `queue` for as long as `isRunning` — each iteration blocks
    /// up to 200ms waiting for NDI's next frame, so this loop is cheap
    /// when nothing's arriving and never spins hot.
    private func pollLoop() {
        while isRunning {
            guard receiver.captureNextFrameTimeoutMs(200) else { continue }
            let size = receiver.pendingFrameSize()
            guard size.width > 0, size.height > 0 else { continue }
            if size != poolSize { setupPool(size: size) }
            guard let pool = pixelBufferPool else { continue }

            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let pixelBuffer else { continue }
            receiver.copyPendingFrame(into: pixelBuffer)

            if let texture = makeTexture(from: pixelBuffer, width: Int(size.width), height: Int(size.height)) {
                os_unfair_lock_lock(&lock)
                _latestTexture = texture
                os_unfair_lock_unlock(&lock)
            }
        }
    }

    private func setupPool(size: CGSize) {
        poolSize = size
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pixelBufferPool)
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> MTLTexture? {
        guard let textureCache else { return nil }
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }
}
