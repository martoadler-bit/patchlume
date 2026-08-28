import AVFoundation
import CoreVideo
import Metal

/// Live front-camera feed as a Metal texture, for the "camera" generator
/// node. Owns its own `AVCaptureSession` — `GraphViewModel` starts/stops it
/// based on whether a camera node is actually present in the graph, so the
/// app never touches the camera (or shows its permission prompt) otherwise.
final class CameraCaptureEngine: NSObject {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.dlrk.luxgraph.camera")
    private var textureCache: CVMetalTextureCache?

    // Written on the capture queue, read on the render thread — same
    // os_unfair_lock snapshot pattern Modula's AudioEngineManager uses for
    // its audio-thread meters.
    private var lock = os_unfair_lock()
    private var _latestTexture: MTLTexture?

    private(set) var isRunning = false
    /// Which physical camera to use — set by `GraphViewModel` from the
    /// camera node's "Lens" parameter. Changing it while already running
    /// tears down and rebuilds the capture input on the camera queue.
    private var position: AVCaptureDevice.Position = .front

    init(device: MTLDevice) {
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    var latestTexture: MTLTexture? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _latestTexture
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        queue.async { [weak self] in self?.configureAndStart() }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        queue.async { [weak self] in self?.session.stopRunning() }
    }

    /// Switches between front/back camera. No-op if already using that lens.
    func setPosition(_ newPosition: AVCaptureDevice.Position) {
        queue.async { [weak self] in
            guard let self, self.position != newPosition else { return }
            self.position = newPosition
            guard !self.session.inputs.isEmpty else { return } // not started yet — beginSession will pick it up
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            self.session.commitConfiguration()
            self.addCameraInput()
            if self.isRunning, !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func configureAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                self?.queue.async { self?.beginSession() }
            }
        default:
            break // denied/restricted — the camera generator just stays black
        }
    }

    private func beginSession() {
        guard session.inputs.isEmpty else {
            if !session.isRunning { session.startRunning() }
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        addCameraInput()

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        applyConnectionSettings(on: output)
        session.commitConfiguration()
        session.startRunning()
    }

    /// Adds the input for whatever `position` currently is — used both for
    /// the initial session build and for a live lens switch. Must be called
    /// between `beginConfiguration()`/`commitConfiguration()` (or standalone
    /// for `setPosition`'s own paired calls).
    private func addCameraInput() {
        session.beginConfiguration()
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        if let output = session.outputs.first as? AVCaptureVideoDataOutput {
            applyConnectionSettings(on: output)
        }
        session.commitConfiguration()
    }

    private func applyConnectionSettings(on output: AVCaptureVideoDataOutput) {
        guard let connection = output.connection(with: .video) else { return }
        connection.videoOrientation = .portrait
        // Mirroring reads naturally for a front-facing selfie feed but looks
        // backwards (text/logos reversed) on the rear camera.
        if connection.isVideoMirroringSupported { connection.isVideoMirrored = position == .front }
    }
}

extension CameraCaptureEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), let textureCache else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return }
        os_unfair_lock_lock(&lock)
        _latestTexture = texture
        os_unfair_lock_unlock(&lock)
    }
}
