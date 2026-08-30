import AVFoundation
import CoreVideo
import Metal
import UIKit

/// Live front-camera feed as a Metal texture, for the "camera" generator
/// node. Owns its own `AVCaptureSession` — `GraphViewModel` starts/stops it
/// based on whether a camera node is actually present in the graph, so the
/// app never touches the camera (or shows its permission prompt) otherwise.
final class CameraCaptureEngine: NSObject {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.dlrk.patchlume.camera")
    private var textureCache: CVMetalTextureCache?

    // Written on the capture queue, read on the render thread — same
    // os_unfair_lock snapshot pattern Modula's AudioEngineManager uses for
    // its audio-thread meters.
    private var lock = os_unfair_lock()
    private var _latestTexture: MTLTexture?

    private(set) var isRunning = false

    /// Mirrors the camera node's "Lens" enum (Front / Back / Back Ultra
    /// Wide) onto the actual physical device + position AVFoundation needs
    /// to pick it.
    enum CameraLens: Int {
        case front = 0
        case back = 1
        case backUltraWide = 2

        var position: AVCaptureDevice.Position { self == .front ? .front : .back }
        var deviceType: AVCaptureDevice.DeviceType { self == .backUltraWide ? .builtInUltraWideCamera : .builtInWideAngleCamera }
    }

    /// Which physical camera to use — set by `GraphViewModel` from the
    /// camera node's "Lens" parameter. Changing it while already running
    /// tears down and rebuilds the capture input on the camera queue.
    private var lens: CameraLens = .back
    private var orientationObserver: NSObjectProtocol?

    // Same lock-protected snapshot pattern as `_latestTexture` — written
    // from the metadata delegate callback (capture queue), read from
    // whoever's asking (`GraphViewModel`'s "faceDetected" Input, the
    // director's shot-change timer, both on the main actor).
    private var faceLock = os_unfair_lock()
    private var _hasFace = false
    /// Up to 3 tracked faces, largest first, normalized (0...1, same
    /// orientation as `latestTexture` since the metadata connection's
    /// `videoOrientation` is kept in lockstep with the video connection's —
    /// see `applyConnectionSettings`). Smoothed frame-to-frame (matched by
    /// nearest previous box, eased rather than snapped) so a "Face Close-Up"
    /// crop doesn't visibly judder on the detector's normal per-frame noise,
    /// and held for a short grace period after a face briefly drops out of
    /// detection (a blink, a fast head turn) rather than instantly
    /// collapsing the crop back to full-frame.
    private var faceBoxLock = os_unfair_lock()
    private var _faceBoxes: [CGRect] = []
    private var missedFaceFrames = 0
    private let faceGraceFrames = 12

    init(device: MTLDevice) {
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    var latestTexture: MTLTexture? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _latestTexture
    }

    /// Whether AVFoundation's built-in (on-device, no model of our own)
    /// face detector currently sees a face in the live frame — drives the
    /// "faceDetected" Input node and the Auto Director's shot-change timer.
    var hasFace: Bool {
        os_unfair_lock_lock(&faceLock)
        defer { os_unfair_lock_unlock(&faceLock) }
        return _hasFace
    }

    /// Up to 3 tracked face rectangles, largest first — drives the "Face
    /// Close-Up" and "Face Grid" modifiers via `RenderEngine.FrameContext`.
    var faceBoxes: [CGRect] {
        os_unfair_lock_lock(&faceBoxLock)
        defer { os_unfair_lock_unlock(&faceBoxLock) }
        return _faceBoxes
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        queue.async { [weak self] in self?.configureAndStart() }
        startObservingOrientation()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        queue.async { [weak self] in self?.session.stopRunning() }
        stopObservingOrientation()
        os_unfair_lock_lock(&faceLock)
        _hasFace = false
        os_unfair_lock_unlock(&faceLock)
        os_unfair_lock_lock(&faceBoxLock)
        _faceBoxes = []
        os_unfair_lock_unlock(&faceBoxLock)
        missedFaceFrames = 0
    }

    /// Keeps the capture connection's orientation matched to however the
    /// device is actually being held, live — without this the camera stays
    /// permanently interpreted as portrait, so rotating to landscape (the
    /// app supports it) delivers a frame rotated 90° from what's actually
    /// in front of the lens. `UIDevice.orientation` needs
    /// `beginGeneratingDeviceOrientationNotifications()` to update at all;
    /// `.faceUp`/`.faceDown`/`.unknown` are ignored (no defined video
    /// orientation) so the last real rotation just holds.
    private func startObservingOrientation() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.applyDeviceOrientation()
        }
        applyDeviceOrientation()
    }

    private func stopObservingOrientation() {
        if let orientationObserver { NotificationCenter.default.removeObserver(orientationObserver) }
        orientationObserver = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func applyDeviceOrientation() {
        guard let videoOrientation = Self.videoOrientation(for: UIDevice.current.orientation) else { return }
        queue.async { [weak self] in
            guard let self, let output = self.session.outputs.first as? AVCaptureVideoDataOutput,
                  let connection = output.connection(with: .video) else { return }
            connection.videoOrientation = videoOrientation
            self.applyMetadataOrientation(videoOrientation)
        }
    }

    /// Keeps the face-detection metadata connection's orientation matched to
    /// the video connection's — `AVMetadataFaceObject.bounds` is reported
    /// relative to whatever orientation ITS OWN connection is set to, which
    /// defaults independently of the video output's, so without this a face
    /// box would land in the wrong place the moment the device is rotated
    /// away from the metadata connection's default.
    ///
    /// Confirmed on-device (2026-08-28): a metadata connection's
    /// `videoOrientation` behaves OPPOSITE the video connection's, not the
    /// same — feeding it the video connection's own value produced a face
    /// box that tracked real movement exactly 180° backwards on both axes
    /// (left/right AND up/down inverted together, i.e. `.portrait` was
    /// being interpreted as `.portraitUpsideDown`). `Self.oppositeOrientation`
    /// corrects for that; this is on top of (not instead of) the separate
    /// landscape-swap gotcha `Self.videoOrientation(for:)` already applies
    /// when converting device orientation to the video connection's value.
    private func applyMetadataOrientation(_ videoOrientation: AVCaptureVideoOrientation) {
        guard let metadataOutput = session.outputs.first(where: { $0 is AVCaptureMetadataOutput }) as? AVCaptureMetadataOutput,
              let connection = metadataOutput.connection(with: .metadata) else { return }
        let orientation = Self.oppositeOrientation(videoOrientation)
        if connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
        // The video connection also mirrors horizontally on the front lens
        // (a natural selfie feed) — without mirroring the metadata
        // connection to match, a tracked face's X lands on the opposite
        // side of where it actually appears in the (mirrored) video
        // texture, so a "Face Close-Up" crop moves with real head motion
        // but centers on the wrong spot.
        if connection.isVideoMirroringSupported { connection.isVideoMirrored = lens == .front }
    }

    /// The camera sensor is physically rotated relative to the device's
    /// "up" — landscape-left/right map to the OPPOSITE `AVCaptureVideoOrientation`
    /// case, not the same-named one (a well-known AVFoundation gotcha).
    private static func videoOrientation(for deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
        switch deviceOrientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil
        }
    }

    /// See `applyMetadataOrientation`. Two on-device results so far, both
    /// wrong in DIFFERENT ways: feeding the metadata connection the SAME
    /// value as the video connection produced a face box exactly 180°
    /// backwards (both axes point-reflected through center); feeding it the
    /// straight opposite (portrait<->portraitUpsideDown) instead produced
    /// the X/Y axes swapped (move up/down and the box moves left/right, and
    /// vice versa) — a 90°-rotation-shaped error, not a 180° one. Those two
    /// results are each one 90° step apart in `AVCaptureVideoOrientation`'s
    /// own raw ordering (portrait=1, portraitUpsideDown=2,
    /// landscapeRight=3, landscapeLeft=4), which is the basis for this
    /// third attempt: advance one MORE step in that same direction
    /// (portrait -> landscapeRight, landscapeRight -> portraitUpsideDown,
    /// etc.) rather than a straight opposite. Flagged as still
    /// experimental — there is no device access to verify this from here,
    /// so if this is wrong too, the remaining untried mapping (the 4th and
    /// last 90°-step option) is the next thing to try.
    private static func oppositeOrientation(_ o: AVCaptureVideoOrientation) -> AVCaptureVideoOrientation {
        switch o {
        case .portrait: return .landscapeRight
        case .landscapeRight: return .portraitUpsideDown
        case .portraitUpsideDown: return .landscapeLeft
        case .landscapeLeft: return .portrait
        @unknown default: return o
        }
    }

    /// Switches lens. No-op if already using that one.
    func setLens(_ newLens: CameraLens) {
        queue.async { [weak self] in
            guard let self, self.lens != newLens else { return }
            self.lens = newLens
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

        // Face detection — AVFoundation's own on-device detector, no
        // separate model/framework needed. Purely additive: if it can't be
        // added for some reason, video capture still works fine, just
        // without the "faceDetected" Input ever reporting true.
        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: queue)
            if metadataOutput.availableMetadataObjectTypes.contains(.face) {
                metadataOutput.metadataObjectTypes = [.face]
            }
            // `applyConnectionSettings` above already ran before this output
            // existed, so seed its orientation here rather than waiting for
            // the next device rotation.
            applyMetadataOrientation(Self.videoOrientation(for: UIDevice.current.orientation) ?? .portrait)
        }

        session.commitConfiguration()
        session.startRunning()
    }

    /// Adds the input for whatever `position` currently is — used both for
    /// the initial session build and for a live lens switch. Must be called
    /// between `beginConfiguration()`/`commitConfiguration()` (or standalone
    /// for `setPosition`'s own paired calls).
    private func addCameraInput() {
        session.beginConfiguration()
        // Ultra-wide isn't on every device (older iPhones/iPads) — fall
        // back to the standard wide-angle lens on that same side rather
        // than leaving the session with no input at all.
        let camera = AVCaptureDevice.default(lens.deviceType, for: .video, position: lens.position)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: lens.position)
        guard let camera,
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
        // Seeds the orientation the session starts with — `applyDeviceOrientation()`
        // only fires again on the NEXT rotation, so a fresh session (or a
        // lens switch, which rebuilds the input) needs its own current
        // reading rather than waiting on a notification that may never come
        // if the device is already sitting in landscape.
        let orientation = Self.videoOrientation(for: UIDevice.current.orientation) ?? .portrait
        connection.videoOrientation = orientation
        applyMetadataOrientation(orientation)
        // Mirroring reads naturally for a front-facing selfie feed but looks
        // backwards (text/logos reversed) on the rear camera.
        if connection.isVideoMirroringSupported { connection.isVideoMirrored = lens == .front }
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

extension CameraCaptureEngine {
    /// Maps a raw `AVMetadataFaceObject.bounds` rect onto true screen UV,
    /// calibrated directly from on-device testing rather than trusted
    /// Apple documentation — `applyMetadataOrientation`'s
    /// `connection.videoOrientation`/`isVideoMirrored` settings turned out
    /// not to reliably steer these bounds the way the API contract
    /// describes, so this replaces relying on that entirely: every
    /// orientation/mirror correction happens HERE, by lens + current
    /// device orientation, against the bounds AVFoundation reports as-is.
    ///
    /// Calibrated data points (2026-08-28, this is empirical, not derived
    /// from documented behavior):
    /// - Front lens, portrait: correct with a straight X/Y transpose, no
    ///   flip needed.
    /// - Back lens, portrait: same transpose, PLUS an X flip — front and
    ///   back sensors are mounted mirrored relative to each other, so the
    ///   same raw bounds need an extra correction on one lens but not the
    ///   other.
    /// - Landscape, bottom edge (charging port) held to the physical LEFT
    ///   (`.landscapeLeft` — `UIDevice`'s naming for this does NOT match
    ///   the intuitive "left/right" reading, confirmed the hard way after
    ///   an earlier attempt had the two cases swapped): no transpose, no
    ///   flip on back; front needs an X-only flip. Bottom edge to the
    ///   physical RIGHT (`.landscapeRight`) is that formula's exact 180°
    ///   mirror, confirmed separately (not just assumed by symmetry) — an
    ///   earlier round conflated the two directions under one "horizontal"
    ///   label without controlling for which was actually held, which is
    ///   what produced two contradictory rounds of landscape data before
    ///   this.
    /// `.portraitUpsideDown` was never tested directly — extrapolated by
    /// symmetry (180°-mirroring the portrait formula) and flagged here as
    /// unverified.
    private func correctedFaceBox(_ raw: CGRect, deviceOrientation: UIDeviceOrientation) -> CGRect {
        switch deviceOrientation {
        case .portrait:
            var cx = raw.midY, cy = raw.midX
            if lens != .front { cx = 1 - cx } // back lens: extra mirror vs. front
            return CGRect(x: cx - raw.height / 2, y: cy - raw.width / 2, width: raw.height, height: raw.width)
        case .portraitUpsideDown:
            // Unverified — the portrait formula mirrored 180° around center.
            var cx = 1 - raw.midY, cy = 1 - raw.midX
            if lens != .front { cx = 1 - cx }
            return CGRect(x: cx - raw.height / 2, y: cy - raw.width / 2, width: raw.height, height: raw.width)
        case .landscapeLeft:
            // Confirmed 2026-08-28 on-device: bottom edge (charging port)
            // held to the physical left — works correctly for both lenses.
            var cx = raw.midX
            let cy = raw.midY
            if lens == .front { cx = 1 - cx }
            return CGRect(x: cx - raw.width / 2, y: cy - raw.height / 2, width: raw.width, height: raw.height)
        case .landscapeRight:
            // 180° mirror of `.landscapeLeft`'s formula (bottom edge held to
            // the physical right) — confirmed 2026-08-28, this direction WAS
            // fully inverted before the two cases got their formulas
            // swapped (an earlier guess had them backwards: assumed
            // `.landscapeRight` was the "bottom edge left" case per a
            // misremembered reading of Apple's naming, which turned out to
            // be the opposite of what `UIDevice.current.orientation`
            // actually reports for that physical position).
            var cx = 1 - raw.midX
            let cy = 1 - raw.midY
            if lens == .front { cx = 1 - cx }
            return CGRect(x: cx - raw.width / 2, y: cy - raw.height / 2, width: raw.width, height: raw.height)
        default:
            return raw // faceUp/faceDown/unknown — no defined mapping, caller's grace period holds the last good box
        }
    }
}

extension CameraCaptureEngine: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let deviceOrientation = UIDevice.current.orientation
        let rawBoxes = metadataObjects.compactMap { $0 as? AVMetadataFaceObject }
            .map { correctedFaceBox($0.bounds, deviceOrientation: deviceOrientation) }
            .sorted { $0.width * $0.height > $1.width * $1.height }
            .prefix(3)

        os_unfair_lock_lock(&faceLock)
        _hasFace = !rawBoxes.isEmpty
        os_unfair_lock_unlock(&faceLock)

        os_unfair_lock_lock(&faceBoxLock)
        if rawBoxes.isEmpty {
            missedFaceFrames += 1
            if missedFaceFrames > faceGraceFrames { _faceBoxes = [] }
            // else: hold the last smoothed boxes through the grace window.
        } else {
            missedFaceFrames = 0
            // Match each new box to the nearest previous one (by center
            // distance) and ease toward it rather than snap — keeps a
            // "Face Close-Up" crop from visibly juddering on the detector's
            // normal per-frame jitter. An unmatched box (a face that just
            // entered frame) starts at its raw position with no smoothing
            // to catch up.
            var smoothed: [CGRect] = []
            for raw in rawBoxes {
                let rawCenter = CGPoint(x: raw.midX, y: raw.midY)
                if let nearest = _faceBoxes.min(by: {
                    hypot($0.midX - rawCenter.x, $0.midY - rawCenter.y) < hypot($1.midX - rawCenter.x, $1.midY - rawCenter.y)
                }), hypot(nearest.midX - rawCenter.x, nearest.midY - rawCenter.y) < 0.25 {
                    let ease: CGFloat = 0.3
                    smoothed.append(CGRect(
                        x: nearest.minX + (raw.minX - nearest.minX) * ease,
                        y: nearest.minY + (raw.minY - nearest.minY) * ease,
                        width: nearest.width + (raw.width - nearest.width) * ease,
                        height: nearest.height + (raw.height - nearest.height) * ease))
                } else {
                    smoothed.append(raw)
                }
            }
            _faceBoxes = smoothed
        }
        os_unfair_lock_unlock(&faceBoxLock)
    }
}
