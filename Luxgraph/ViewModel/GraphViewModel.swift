import AVFoundation
import Combine
import CoreGraphics
import Foundation
import Metal

/// The single layer that connects SwiftUI to `GraphStore` plus the audio
/// and MIDI engines — the canvas, inspector, and preview all read/write
/// through this one object.
@MainActor
final class GraphViewModel: ObservableObject {
    let store = GraphStore()
    let audio = AudioReactivityEngine()
    let midi = MIDIManager()
    let renderEngine = RenderEngine()
    let cameraEngine = CameraCaptureEngine(device: MTLCreateSystemDefaultDevice()!)
    lazy var mediaTextureEngine = MediaTextureEngine(device: renderEngine.device)
    lazy var textTextureEngine = TextTextureEngine(device: renderEngine.device)
    // `renderEngine.device`, not a fresh `MTLCreateSystemDefaultDevice()` —
    // same "share one device" reasoning as the preview MTKViews and
    // CameraCaptureEngine: this recorder blits directly from textures
    // RenderEngine's own command queue produced.
    lazy var videoRecorder = VideoRecorder(device: renderEngine.device)

    private var startTime = Date()
    private var cancellables: Set<AnyCancellable> = []

    // Per-node runtime state for the two stateful Input types (everything
    // else is a pure function of node params + FrameContext). Keyed by node
    // id; a stale entry for a deleted node just sits there harmlessly.
    private var envelopeState: [UUID: Float] = [:]
    private var sampleHoldState: [UUID: (value: Float, phase: Float)] = [:]

    init() {
        store.load(GraphTemplateCatalog.starter())
        wireRenderEngine()
        // Re-publish so SwiftUI observers of GraphViewModel refresh when the
        // underlying store or audio engine changes (both are their own
        // ObservableObjects; this bridges their changes upward for any view
        // that only holds a GraphViewModel).
        store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        audio.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        // Camera only ever runs while a Camera generator node actually
        // exists somewhere in the current graph — never touched (and its
        // permission prompt never shown) otherwise. $graph (unlike
        // objectWillChange) delivers the post-change value, including an
        // initial emission right away for the starter graph.
        store.$graph.sink { [weak self] graph in
            guard let self else { return }
            let cameraNodes = graph.nodes.filter { $0.kind == .generator && $0.subtype == "camera" }
            if cameraNodes.isEmpty {
                self.cameraEngine.stop()
            } else {
                self.cameraEngine.start()
                // Only one physical camera session exists; if multiple
                // camera nodes disagree on lens, the first one wins.
                let wantsBack = (cameraNodes.first?.parameters["p2"] ?? 0) >= 0.5
                self.cameraEngine.setPosition(wantsBack ? .back : .front)
            }
            let nodeIDs = Set(graph.nodes.map(\.id))
            self.mediaTextureEngine.pruneStale(keeping: nodeIDs)
            self.textTextureEngine.pruneStale(keeping: nodeIDs)
        }.store(in: &cancellables)
        // The external-display scene delegate is instantiated by UIKit
        // itself when a screen connects, with no way to hand it this
        // engine directly — this is the one shared place it looks for it.
        ExternalDisplayManager.shared.renderEngine = renderEngine
        ExternalDisplayManager.shared.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        // Force-create now so `renderEngine.videoRecorder` is wired before
        // anything could try to start a recording.
        renderEngine.videoRecorder = videoRecorder
        videoRecorder.onNeedsFrame = { [weak self] in self?.renderEngine.captureFrameForRecording() }
        videoRecorder.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    private func wireRenderEngine() {
        renderEngine.graphProvider = { [weak self] in self?.store.graph ?? .empty }
        renderEngine.frameContextProvider = { [weak self] in
            guard let self else { return RenderEngine.FrameContext() }
            let elapsed = Float(Date().timeIntervalSince(self.startTime))
            let bands = self.audio.state
            return RenderEngine.FrameContext(
                time: elapsed,
                beat: bands.beat,
                beatStrength: bands.beatStrength,
                bass: bands.bass,
                mid: bands.mid,
                treble: bands.treble,
                energy: bands.energy
            )
        }
        renderEngine.inputValueProvider = { [weak self] node, context in
            self?.value(forInputNode: node, context: context) ?? 0
        }
        renderEngine.resolvedParameterProvider = { [weak self] node, context in
            self?.resolvedParameters(for: node, context: context) ?? node.parameters
        }
        renderEngine.cameraTextureProvider = { [weak self] in self?.cameraEngine.latestTexture }
        renderEngine.mediaTextureProvider = { [weak self] node in self?.mediaTextureEngine.texture(for: node) }
        renderEngine.textTextureProvider = { [weak self] node in self?.textTextureEngine.texture(for: node) }
    }

    /// Folds a node's Macro assignments and inline per-parameter LFOs into
    /// its base dialed-in values, clamped back into each parameter's
    /// declared range. A Macro assignment REPLACES the base value outright
    /// (an explicit rangeMin...rangeMax sweep — see `MacroAssignment`), so
    /// it's applied first; the inline LFO's offset then stacks additively
    /// on top of whatever that leaves. The cable-based "mod" port resolves
    /// separately inside the shader via `modValue` (unchanged, targets only
    /// the primary parameter) and stacks with both of these too.
    private func resolvedParameters(for node: GraphNode, context: RenderEngine.FrameContext) -> [String: Float] {
        var result = node.parameters
        guard !node.paramModulators.isEmpty || !store.graph.macroAssignments.isEmpty else { return result }
        let descriptors = NodeCatalog.parameters(kind: node.kind, subtype: node.subtype)
        for descriptor in descriptors {
            var value = result[descriptor.id] ?? descriptor.defaultValue
            for assignment in store.graph.macroAssignments where assignment.nodeID == node.id && assignment.paramID == descriptor.id {
                guard let macro = store.graph.macros.first(where: { $0.id == assignment.macroID }) else { continue }
                value = assignment.rangeMin + (assignment.rangeMax - assignment.rangeMin) * macro.value
            }
            if let modulator = node.paramModulators[descriptor.id] {
                let range = descriptor.maxValue - descriptor.minValue
                let phase = context.time * modulator.rate
                value += lfoWaveform(phase: phase, shape: modulator.shape) * modulator.depth * range * 0.5
            }
            result[descriptor.id] = value.clamped(descriptor.minValue, descriptor.maxValue)
        }
        return result
    }

    /// Resolves an Input node's live 0...1 output value each frame.
    private func value(forInputNode node: GraphNode, context: RenderEngine.FrameContext) -> Float {
        switch node.subtype {
        case "time":
            return context.time.truncatingRemainder(dividingBy: 10) / 10
        case "lfo":
            let rate = node.parameters["p0"] ?? 1
            let shape = Int(node.parameters["p1"] ?? 0)
            // Shares `lfoWaveform` with the inline per-parameter modulator
            // (Core/Graph/Modulation.swift) so "Triangle" (etc.) looks and
            // moves identically whichever of the two ways it's patched in —
            // this used to have its own hand-rolled switch whose triangle
            // case was accidentally phase-inverted relative to the shared
            // one (sine/square/saw already matched by coincidence).
            return 0.5 + 0.5 * lfoWaveform(phase: context.time * rate, shape: shape)
        case "constant":
            return node.parameters["p0"] ?? 0.5
        case "bass": return context.bass
        case "mid": return context.mid
        case "treble": return context.treble
        case "energy": return context.energy
        case "beatStrength": return context.beatStrength
        case "midiCC":
            let cc = Int(node.parameters["p0"] ?? 1)
            return midi.value(forCC: cc)
        case "midiNote":
            return midi.latestActiveNoteValue()
        case "envelope":
            let attack = max(0.01, node.parameters["p0"] ?? 0.15)
            let release = max(0.01, node.parameters["p1"] ?? 0.35)
            let source = Int(node.parameters["p2"] ?? 0)
            let target: Float
            switch source {
            case 1: target = context.bass
            case 2: target = context.mid
            case 3: target = context.treble
            default: target = context.energy
            }
            let previous = envelopeState[node.id] ?? 0
            // One-pole follower; attack/release are "how much of the gap to
            // close per frame" rather than true seconds — simple, and good
            // enough at a roughly-60fps render loop.
            let coefficient = target > previous ? attack : release
            let next = previous + (target - previous) * coefficient
            envelopeState[node.id] = next
            return next
        case "sampleHold":
            let rate = max(0.05, node.parameters["p0"] ?? 2)
            let phase = (context.time * rate).truncatingRemainder(dividingBy: 1)
            var state = sampleHoldState[node.id] ?? (value: Float.random(in: 0...1), phase: phase)
            if phase < state.phase { state.value = Float.random(in: 0...1) } // wrapped -> new hold
            state.phase = phase
            sampleHoldState[node.id] = state
            return state.value
        case "clock":
            let bpm = max(20, node.parameters["p0"] ?? 120)
            let divisions: [Float] = [1, 2, 4, 8, 16]
            let division = divisions[min(max(Int(node.parameters["p1"] ?? 2), 0), divisions.count - 1)]
            let beatLength = 60 / bpm / division
            let phase = context.time.truncatingRemainder(dividingBy: beatLength) / beatLength
            return max(0, 1 - phase * 3)
        case "noise":
            let rate = max(0.05, node.parameters["p0"] ?? 0.5)
            let t = context.time * rate
            let i0 = floor(t), i1 = i0 + 1
            let f = t - i0
            let smooth = f * f * (3 - 2 * f)
            func hash(_ x: Float) -> Float {
                let s = sin(x * 12.9898) * 43758.5453
                return s - floor(s)
            }
            return hash(i0) + (hash(i1) - hash(i0)) * smooth
        case "sequencer":
            // A deterministic, held-per-step pattern (not continuous noise
            // like Sample & Hold) quantized to Clock's BPM/Division grid —
            // the same `steps` step index always lands on the same value,
            // so the pattern audibly/visually repeats every cycle instead
            // of drifting.
            let steps = max(2, Int(node.parameters["p0"] ?? 8))
            let bpm = max(20, node.parameters["p1"] ?? 120)
            let divisions: [Float] = [1, 2, 4, 8, 16]
            let division = divisions[min(max(Int(node.parameters["p2"] ?? 2), 0), divisions.count - 1)]
            let stepLength = 60 / bpm / division
            let stepIndex = Int(context.time / stepLength) % steps
            let seed = Float(stepIndex) * 12.9898
            let s = sin(seed) * 43758.5453
            return s - floor(s)
        default:
            return 0
        }
    }

    // MARK: - Convenience passthroughs for the views

    var nodes: [GraphNode] { store.nodes }
    var connections: [GraphConnection] { store.connections }
    var selectedNodeID: UUID? {
        get { store.selectedNodeID }
        set { store.selectedNodeID = newValue }
    }

    func newGraph() {
        store.load(Graph.empty)
        currentPatchID = nil
        currentPatchName = "Untitled"
    }

    func loadTemplate(_ template: GraphTemplateCatalog.Template) {
        store.load(template.make())
        currentPatchID = nil
        currentPatchName = template.name
    }

    // MARK: - Saved patches

    /// nil until the working graph has been saved (or was loaded from a
    /// save) at least once this session — lets repeated saves overwrite
    /// the same file instead of piling up a new one every time.
    @Published private(set) var currentPatchID: UUID?
    @Published var currentPatchName: String = "Untitled"

    func savePatch(named name: String) {
        let id = currentPatchID ?? UUID()
        let patch = SavedPatch(id: id, name: name, graph: store.graph)
        do {
            try PatchStore.save(patch)
            currentPatchID = id
            currentPatchName = name
        } catch {
            print("Luxgraph: failed to save patch \"\(name)\": \(error)")
        }
    }

    func loadSavedPatch(_ patch: SavedPatch) {
        store.load(patch.graph)
        currentPatchID = patch.id
        currentPatchName = patch.name
    }
}
