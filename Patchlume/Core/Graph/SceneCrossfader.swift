import Combine
import CoreGraphics
import Foundation

/// Shared smooth-transition engine between two complete graphs — splices
/// both into one temporary graph merged by a fresh Blend combiner, ramps
/// its Mix 0->1 over a few seconds, then swaps to the destination graph
/// alone. Originally lived inside `AutoDirectorEngine`; pulled out so
/// `SceneBankView` (a performer tapping a scene button by hand) gets the
/// exact same crossfade a moment the director picks automatically, rather
/// than two copies of this logic slowly drifting apart.
@MainActor
final class SceneCrossfader: ObservableObject {
    @Published private(set) var isTransitioning = false

    private weak var store: GraphStore?
    private var transitionTimer: Timer?
    private let transitionSeconds: Double
    private let transitionSteps: Int

    init(store: GraphStore, transitionSeconds: Double = 2.5, transitionSteps: Int = 30) {
        self.store = store
        self.transitionSeconds = transitionSeconds
        self.transitionSteps = transitionSteps
    }

    /// Crossfades from whatever the store's CURRENT graph is to
    /// `nextGraph`. Cancels any crossfade already in progress — a fresh
    /// tap (or the director's own next pick) always wins over a stale one
    /// rather than queuing behind it. `completion` fires once `nextGraph`
    /// is fully current (immediately, if a fallback hard cut was needed
    /// because one of the two graphs had no Output).
    func crossfade(to nextGraph: Graph, completion: (() -> Void)? = nil) {
        guard let store else { return }
        transitionTimer?.invalidate()

        let previousGraph = store.graph
        guard let built = Self.buildCrossfadeGraph(from: previousGraph, to: nextGraph) else {
            store.load(nextGraph, resetHistory: false)
            isTransitioning = false
            completion?()
            return
        }

        store.load(built.graph, resetHistory: false)
        isTransitioning = true
        var step = 0
        transitionTimer = Timer.scheduledTimer(withTimeInterval: transitionSeconds / Double(transitionSteps), repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, let store = self.store else { timer.invalidate(); return }
                step += 1
                let mix = Float(step) / Float(self.transitionSteps)
                store.updateParameter(nodeID: built.blendNodeID, paramID: "p0", value: mix, recordUndo: false)
                if step >= self.transitionSteps {
                    timer.invalidate()
                    store.load(nextGraph, resetHistory: false)
                    self.isTransitioning = false
                    completion?()
                }
            }
        }
    }

    /// Splices two complete scene graphs into one: both graphs' nodes
    /// (minus each one's own Output node), merged by a fresh Blend
    /// combiner whose Mix (`p0`) the transition timer ramps 0->1, feeding
    /// one new shared Output. Node IDs are all fresh UUIDs per graph
    /// (`GraphTemplateCatalog.build()`/`AutoDirectorScenes` mint new ones
    /// every call), so the two node sets never collide.
    private static func buildCrossfadeGraph(from a: Graph, to b: Graph) -> (graph: Graph, blendNodeID: UUID)? {
        guard let outputA = a.nodes.first(where: { $0.kind == .output }),
              let sourceAID = a.textureSources(into: outputA.id)["in"],
              let outputB = b.nodes.first(where: { $0.kind == .output }),
              let sourceBID = b.textureSources(into: outputB.id)["in"] else { return nil }

        var blendNode = NodeCatalog.makeNode(kind: .combiner, subtype: "blend", position: CGPoint(x: 900, y: 900))
        blendNode.parameters["p0"] = 0 // starts fully on scene A, ramped up to scene B
        blendNode.parameters["p1"] = 3 // "Mix" mode — a plain crossfade, not additive/screen
        let output = NodeCatalog.makeNode(kind: .output, subtype: "output", position: CGPoint(x: 1200, y: 900))

        var graph = Graph.empty
        graph.nodes = a.nodes.filter { $0.kind != .output } + b.nodes.filter { $0.kind != .output } + [blendNode, output]
        graph.connections = a.connections.filter { $0.destNodeID != outputA.id } + b.connections.filter { $0.destNodeID != outputB.id } + [
            GraphConnection(sourceNodeID: sourceAID, sourcePortID: "out", destNodeID: blendNode.id, destPortID: "inA", signalType: .texture),
            GraphConnection(sourceNodeID: sourceBID, sourcePortID: "out", destNodeID: blendNode.id, destPortID: "inB", signalType: .texture),
            GraphConnection(sourceNodeID: blendNode.id, sourcePortID: "out", destNodeID: output.id, destPortID: "in", signalType: .texture),
        ]
        // Carry both graphs' macros forward so anything riding them (the
        // director's macro rider, or just their own inline LFOs resolving
        // each frame) keeps performing through the crossfade instead of
        // going still for its duration — node IDs are untouched, so each
        // macro's routes still land on the right (now-merged) nodes.
        graph.macros = a.macros + b.macros
        graph.macroAssignments = a.macroAssignments + b.macroAssignments
        return (graph, blendNode.id)
    }
}
