import Combine
import CoreGraphics
import Foundation

/// Owns the current graph plus JSON-snapshot undo/redo — same simple
/// "push a full snapshot before every meaningful edit" approach Modula's
/// PatchViewModel uses rather than a diff-based undo stack.
@MainActor
final class GraphStore: ObservableObject {
    @Published private(set) var graph: Graph = .empty
    @Published var selectedNodeID: UUID?
    /// Canvas display state, not part of the graph itself (not saved/undone
    /// with it) — same role as Modula's `cablesHidden` toggle: hide every
    /// cable to declutter a busy patch without disconnecting anything.
    /// Starts (and resets on every `load`) hidden — cables showing by
    /// default on a freshly-opened template read as clutter before you've
    /// even looked at the nodes; "Show Cables" is one tap away.
    @Published var cablesHidden = true
    /// Collapses the live preview strip down to a thin re-open bar, freeing
    /// its space for the canvas/controls — most useful once an external
    /// display is showing the clean feed already (see `ExternalDisplayManager`)
    /// and the phone/iPad screen doesn't need to duplicate it too.
    @Published var previewHidden = false
    /// Bumped whenever a whole new graph is loaded (template, undo across a
    /// load) so the canvas knows to re-run fitToContent.
    @Published private(set) var fitRequestToken = UUID()

    private var undoStack: [Data] = []
    private var redoStack: [Data] = []
    private let maxHistory = 60

    var nodes: [GraphNode] { graph.nodes }
    var connections: [GraphConnection] { graph.connections }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func node(_ id: UUID) -> GraphNode? { graph.node(id) }

    func load(_ newGraph: Graph, resetHistory: Bool = true) {
        graph = newGraph
        if resetHistory {
            undoStack.removeAll()
            redoStack.removeAll()
        }
        selectedNodeID = nil
        cablesHidden = true
        fitRequestToken = UUID()
    }

    // MARK: - Mutations (each snapshots first, for undo)

    /// Returns the new node's id (needed by Lesson/Challenge `buildActions`
    /// playback to wire it up right after). Deliberately does NOT select
    /// it — selecting a node opens the Inspector panel, and popping that
    /// open every time someone taps a node in the library was more
    /// disruptive than helpful; the node still appears on the canvas
    /// (auto-framed) so it's easy to find and tap open on purpose.
    @discardableResult
    func addNode(kind: NodeKind, subtype: String, near preferredStart: CGPoint? = nil) -> UUID {
        snapshotForUndo()
        let position = GraphLayoutEngine.nextFreePosition(for: kind, avoiding: graph.nodes, near: preferredStart)
        let node = NodeCatalog.makeNode(kind: kind, subtype: subtype, position: position)
        graph.nodes.append(node)
        return node.id
    }

    func removeNode(id: UUID) {
        snapshotForUndo()
        graph.nodes.removeAll { $0.id == id }
        graph.connections.removeAll { $0.sourceNodeID == id || $0.destNodeID == id }
        graph.macroAssignments.removeAll { $0.nodeID == id }
        if selectedNodeID == id { selectedNodeID = nil }
    }

    func duplicateNode(id: UUID) {
        guard let original = graph.node(id) else { return }
        snapshotForUndo()
        var copy = original
        let newID = UUID()
        copy = GraphNode(id: newID, kind: original.kind, subtype: original.subtype,
                          position: GraphLayoutEngine.nextFreePosition(for: original.kind, avoiding: graph.nodes, near: CGPoint(x: original.position.x + 40, y: original.position.y + 40)),
                          parameters: original.parameters, paramModulators: original.paramModulators, mediaRef: original.mediaRef, textContent: original.textContent)
        graph.nodes.append(copy)
        selectedNodeID = newID
    }

    func updatePosition(id: UUID, position: CGPoint) {
        guard let index = graph.nodes.firstIndex(where: { $0.id == id }) else { return }
        graph.nodes[index].position = position
    }

    func updateParameter(nodeID: UUID, paramID: String, value: Float, recordUndo: Bool = true) {
        guard let index = graph.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        if recordUndo { snapshotForUndo() }
        graph.nodes[index].parameters[paramID] = value
    }

    @discardableResult
    func connect(source: PortKey, dest: PortKey) -> Bool {
        guard source.direction == .output, dest.direction == .input, source.nodeID != dest.nodeID else { return false }
        let sourcePorts = NodeCatalog.ports(kind: graph.node(source.nodeID)?.kind ?? .generator)
        guard let sourcePort = sourcePorts.outputs.first(where: { $0.id == source.portID }) else { return false }
        let destPorts = NodeCatalog.ports(kind: graph.node(dest.nodeID)?.kind ?? .generator)
        guard let destPort = destPorts.inputs.first(where: { $0.id == dest.portID }) else { return false }
        guard sourcePort.signalType == destPort.signalType else { return false }

        snapshotForUndo()
        // Each input port accepts exactly one cable — replace any existing one.
        graph.connections.removeAll { $0.destNodeID == dest.nodeID && $0.destPortID == dest.portID }
        let connection = GraphConnection(sourceNodeID: source.nodeID, sourcePortID: source.portID, destNodeID: dest.nodeID, destPortID: dest.portID, signalType: sourcePort.signalType)
        graph.connections.append(connection)
        return true
    }

    func disconnectAll(forNodeID id: UUID) {
        guard hasAnyConnections(nodeID: id) else { return }
        snapshotForUndo()
        graph.connections.removeAll { $0.sourceNodeID == id || $0.destNodeID == id }
    }

    func disconnect(portKey: PortKey) {
        let matches = graph.connections.filter {
            (portKey.direction == .output && $0.sourceNodeID == portKey.nodeID && $0.sourcePortID == portKey.portID) ||
            (portKey.direction == .input && $0.destNodeID == portKey.nodeID && $0.destPortID == portKey.portID)
        }
        guard !matches.isEmpty else { return }
        snapshotForUndo()
        let ids = Set(matches.map(\.id))
        graph.connections.removeAll { ids.contains($0.id) }
    }

    func hasAnyConnections(nodeID: UUID) -> Bool {
        graph.connections.contains { $0.sourceNodeID == nodeID || $0.destNodeID == nodeID }
    }

    // MARK: - Inline per-parameter modulation

    /// `nil` removes whatever modulator the parameter has.
    func setParamModulator(nodeID: UUID, paramID: String, modulator: ParamModulator?) {
        guard let index = graph.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        snapshotForUndo()
        graph.nodes[index].paramModulators[paramID] = modulator
    }

    /// Points a "media" generator node at a photo/video already imported
    /// into `MediaStore` (nil clears it back to blank).
    func setMediaRef(nodeID: UUID, ref: String?) {
        guard let index = graph.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        snapshotForUndo()
        graph.nodes[index].mediaRef = ref
    }

    /// Sets a "text" generator node's displayed string.
    func setTextContent(nodeID: UUID, text: String) {
        guard let index = graph.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        snapshotForUndo()
        graph.nodes[index].textContent = text
    }

    // MARK: - Macros

    @discardableResult
    func addMacro(name: String) -> Macro {
        snapshotForUndo()
        let macro = Macro(name: name)
        graph.macros.append(macro)
        return macro
    }

    func renameMacro(id: UUID, name: String) {
        guard let index = graph.macros.firstIndex(where: { $0.id == id }) else { return }
        snapshotForUndo()
        graph.macros[index].name = name
    }

    func removeMacro(id: UUID) {
        guard graph.macros.contains(where: { $0.id == id }) else { return }
        snapshotForUndo()
        graph.macros.removeAll { $0.id == id }
        graph.macroAssignments.removeAll { $0.macroID == id }
    }

    /// Live performance turn of a macro knob — deliberately NOT snapshotted,
    /// same reasoning as why turning a regular parameter knob only snapshots
    /// once per drag rather than per pixel (see `updateParameter`); this one
    /// never snapshots at all since it's meant to be ridden continuously
    /// while watching the preview.
    func updateMacroValue(id: UUID, value: Float) {
        guard let index = graph.macros.firstIndex(where: { $0.id == id }) else { return }
        graph.macros[index].value = value.clamped(0, 1)
    }

    /// The assignment routed from `macroID` into `nodeID`'s `paramID`, if
    /// any — lets matrix/panel UI read it without hunting the list itself.
    func macroAssignment(macroID: UUID, nodeID: UUID, paramID: String) -> MacroAssignment? {
        graph.macroAssignments.first { $0.macroID == macroID && $0.nodeID == nodeID && $0.paramID == paramID }
    }

    /// Every assignment belonging to one macro, for the macro panel's
    /// per-macro target list.
    func macroAssignments(for macroID: UUID) -> [MacroAssignment] {
        graph.macroAssignments.filter { $0.macroID == macroID }
    }

    /// Creates or updates the single assignment for this (macro, node,
    /// parameter) triple.
    func setMacroAssignment(macroID: UUID, nodeID: UUID, paramID: String, rangeMin: Float, rangeMax: Float) {
        snapshotForUndo()
        graph.macroAssignments.removeAll { $0.macroID == macroID && $0.nodeID == nodeID && $0.paramID == paramID }
        graph.macroAssignments.append(MacroAssignment(macroID: macroID, nodeID: nodeID, paramID: paramID, rangeMin: rangeMin, rangeMax: rangeMax))
    }

    func removeMacroAssignment(macroID: UUID, nodeID: UUID, paramID: String) {
        guard graph.macroAssignments.contains(where: { $0.macroID == macroID && $0.nodeID == nodeID && $0.paramID == paramID }) else { return }
        snapshotForUndo()
        graph.macroAssignments.removeAll { $0.macroID == macroID && $0.nodeID == nodeID && $0.paramID == paramID }
    }

    // MARK: - Undo/redo

    private func snapshotForUndo() {
        guard let data = try? JSONEncoder().encode(graph) else { return }
        undoStack.append(data)
        if undoStack.count > maxHistory { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let data = undoStack.popLast(), let previous = try? JSONDecoder().decode(Graph.self, from: data) else { return }
        if let current = try? JSONEncoder().encode(graph) { redoStack.append(current) }
        graph = previous
        selectedNodeID = nil
    }

    func redo() {
        guard let data = redoStack.popLast(), let next = try? JSONDecoder().decode(Graph.self, from: data) else { return }
        if let current = try? JSONEncoder().encode(graph) { undoStack.append(current) }
        graph = next
        selectedNodeID = nil
    }

    func requestFit() {
        fitRequestToken = UUID()
    }
}
