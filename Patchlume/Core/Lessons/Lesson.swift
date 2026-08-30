import Foundation

/// One scripted move in a self-playing tutorial: add a node, wire a cable,
/// nudge a parameter. `ref` is a short local name (e.g. "gen") used only to
/// wire later actions in the same step to a node added earlier in it — it's
/// never shown to the user and isn't a real node id. Ported from Modula's
/// `TutorialAction` (Module -> Node, Patch -> Graph).
struct TutorialAction {
    enum Kind {
        case addNode(ref: String, nodeKind: NodeKind, subtype: String, parameters: [String: Float])
        case connect(fromRef: String, outPort: String, toRef: String, inPort: String)
        case setParameter(ref: String, parameterID: String, value: Float)
    }

    /// Updates the speech bubble the moment this action plays. `nil` leaves
    /// whatever caption is already showing.
    let caption: String?
    let kind: Kind

    static func addNode(_ ref: String, _ nodeKind: NodeKind, _ subtype: String, _ parameters: [String: Float] = [:], caption: String? = nil) -> TutorialAction {
        TutorialAction(caption: caption, kind: .addNode(ref: ref, nodeKind: nodeKind, subtype: subtype, parameters: parameters))
    }

    static func connect(_ fromRef: String, _ outPort: String, _ toRef: String, _ inPort: String, caption: String? = nil) -> TutorialAction {
        TutorialAction(caption: caption, kind: .connect(fromRef: fromRef, outPort: outPort, toRef: toRef, inPort: inPort))
    }

    static func setParameter(_ ref: String, _ parameterID: String, _ value: Float, caption: String? = nil) -> TutorialAction {
        TutorialAction(caption: caption, kind: .setParameter(ref: ref, parameterID: parameterID, value: value))
    }

    /// Applies this one action to `store`, resolving/recording refs via
    /// `refToNodeID`. Shared by `LessonViewModel`'s step playback and
    /// `ChallengeViewModel`'s "Show Me" solution playback so the two stay
    /// in sync — there is exactly one place that knows what an `addNode`/
    /// `connect`/`setParameter` action actually does to a graph.
    @MainActor
    func apply(to store: GraphStore, refToNodeID: inout [String: UUID]) {
        switch kind {
        case .addNode(let ref, let nodeKind, let subtype, let parameters):
            let newID = store.addNode(kind: nodeKind, subtype: subtype)
            for (parameterID, value) in parameters {
                store.updateParameter(nodeID: newID, paramID: parameterID, value: value, recordUndo: false)
            }
            refToNodeID[ref] = newID
            store.requestFit()

        case .connect(let fromRef, let outPort, let toRef, let inPort):
            guard let fromID = refToNodeID[fromRef], let toID = refToNodeID[toRef] else { return }
            store.connect(source: PortKey(nodeID: fromID, portID: outPort, direction: .output),
                           dest: PortKey(nodeID: toID, portID: inPort, direction: .input))

        case .setParameter(let ref, let parameterID, let value):
            guard let id = refToNodeID[ref] else { return }
            store.updateParameter(nodeID: id, paramID: parameterID, value: value)
        }
    }
}

/// One screen of a lesson. Most steps are read-and-try-it-yourself: some
/// explanatory text, optionally a graph to load so the canvas has something
/// concrete to point at, optionally a node kind to highlight. A step can
/// instead carry `buildActions` — a scripted sequence that plays itself out
/// on the canvas (node by node, cable by cable) while the caption narrates,
/// for a "watch it get built" tutorial instead of a hands-on one. Ported
/// from Modula's `LessonStep`.
struct LessonStep {
    let text: String
    let graphToLoad: Graph?
    let highlightKind: NodeKind?
    /// The specific subtype this step is about, when known — lets a step
    /// highlight e.g. only "bass" Input nodes instead of every Input.
    let highlightSubtype: String?
    /// The specific node instance this step is about, when known (e.g. an
    /// auto-generated `GraphTourBuilder` step). Lets the canvas pan/zoom to
    /// the exact node being discussed instead of only glowing every node of
    /// a given kind — needed once a graph has two of the same kind.
    let highlightNodeID: UUID?
    let buildActions: [TutorialAction]

    init(text: String, graphToLoad: Graph? = nil, highlightKind: NodeKind? = nil, highlightSubtype: String? = nil, highlightNodeID: UUID? = nil, buildActions: [TutorialAction] = []) {
        self.text = text
        self.graphToLoad = graphToLoad
        self.highlightKind = highlightKind
        self.highlightSubtype = highlightSubtype
        self.highlightNodeID = highlightNodeID
        self.buildActions = buildActions
    }
}

struct Lesson: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let icon: String
    let steps: [LessonStep]
}
