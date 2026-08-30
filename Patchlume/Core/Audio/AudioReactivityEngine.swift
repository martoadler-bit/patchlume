import Accelerate
import AVFoundation
import Foundation

enum AudioSource: String, CaseIterable, Identifiable {
    case mic = "Mic"
    case sim = "Sim"
    var id: String { rawValue }
}

/// Live audio-reactivity values consumed by the render engine each frame.
struct BeatState {
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var energy: Float = 0
    var beat: Float = 0
    var beatStrength: Float = 0
}

/// `AVAudioEngine` mic tap + Accelerate FFT band averaging, with a simple
/// bass-transient-over-rolling-average beat detector — same logic shape as
/// a typical web audio-reactivity module, rewritten natively. Also offers a
/// "Sim" mode: a clean synthetic BPM pulse with no real audio, so the app is
/// demoable in Simulator (no mic) or anywhere a live source is inconvenient.
@MainActor
final class AudioReactivityEngine: ObservableObject {
    @Published private(set) var state = BeatState()
    @Published var source: AudioSource = .sim {
        didSet { handleSourceChange() }
    }
    @Published private(set) var isMicAuthorized = true

    private let engine = AVAudioEngine()
    private var fftSetup: FFTSetup?
    private let fftSize = 1024
    private let log2n: UInt

    private var rollingBassAverage: Float = 0
    private var lastBeatTime: TimeInterval = 0
    private var simPhase: Float = 0

    private var displayLink: Timer?

    init() {
        log2n = UInt(round(log2(Double(fftSize))))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        startClock()
    }

    deinit {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    private func startClock() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickSim() }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayLink = timer
        handleSourceChange()
    }

    private func handleSourceChange() {
        switch source {
        case .mic:
            startMic()
        case .sim:
            stopMic()
        }
    }

    private func tickSim() {
        guard source == .sim else { return }
        simPhase += 1.0 / 60.0
        let bpm: Float = 120
        let beatPeriod = 60.0 / bpm
        let phaseInBeat = simPhase.truncatingRemainder(dividingBy: beatPeriod) / beatPeriod
        let pulse = max(0, 1 - phaseInBeat * 4)
        state.bass = 0.3 + pulse * 0.6
        state.mid = 0.25 + 0.2 * (0.5 + 0.5 * sin(simPhase * 3))
        state.treble = 0.2 + 0.15 * (0.5 + 0.5 * sin(simPhase * 5.3))
        state.energy = (state.bass + state.mid + state.treble) / 3
        state.beatStrength = pulse
        state.beat = pulse > 0.9 ? 1 : 0
    }

    private func startMic() {
        let session = AVAudioSession.sharedInstance()
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.isMicAuthorized = granted
                guard granted else {
                    self.source = .sim
                    return
                }
                do {
                    // Activate the session before touching any audio engine
                    // endpoint, or the tap silently never delivers buffers.
                    try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
                    try session.setActive(true)
                    self.installTap()
                } catch {
                    self.source = .sim
                }
            }
        }
    }

    private func installTap() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let magnitudes = Self.magnitudes(from: buffer, fftSize: self.fftSize, log2n: self.log2n, setup: self.fftSetup)
            Task { @MainActor in
                self.applyBands(magnitudes, sampleRate: Float(format.sampleRate))
            }
        }
        do {
            try engine.start()
        } catch {
            source = .sim
        }
    }

    private func stopMic() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
    }

    private nonisolated static func magnitudes(from buffer: AVAudioPCMBuffer, fftSize: Int, log2n: UInt, setup: FFTSetup?) -> [Float] {
        guard let setup, let channelData = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        guard frameCount >= fftSize else { return [] }

        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(channelData[0], 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { windowedPtr in
                    windowedPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }
        return magnitudes
    }

    private func applyBands(_ magnitudes: [Float], sampleRate: Float) {
        guard !magnitudes.isEmpty, sampleRate > 0 else { return }
        let binHz = sampleRate / Float(fftSize)
        func average(_ loHz: Float, _ hiHz: Float) -> Float {
            let lo = max(0, Int(loHz / binHz))
            let hi = min(magnitudes.count - 1, Int(hiHz / binHz))
            guard hi > lo else { return 0 }
            var sum: Float = 0
            for i in lo...hi { sum += magnitudes[i] }
            let avg = sum / Float(hi - lo + 1)
            return min(1, sqrt(avg) * 0.02)
        }

        let bass = average(20, 250)
        let mid = average(250, 2000)
        let treble = average(2000, 8000)
        let energy = (bass + mid + treble) / 3

        rollingBassAverage = rollingBassAverage * 0.9 + bass * 0.1
        let transient = bass - rollingBassAverage
        let now = CACurrentMediaTime()
        var beat: Float = 0
        var beatStrength = state.beatStrength * 0.85
        if transient > 0.12, now - lastBeatTime > 0.2 {
            beat = 1
            beatStrength = min(1, transient * 3)
            lastBeatTime = now
        }

        state.bass = bass
        state.mid = mid
        state.treble = treble
        state.energy = energy
        state.beat = beat
        state.beatStrength = max(beatStrength, 0)
    }
}
