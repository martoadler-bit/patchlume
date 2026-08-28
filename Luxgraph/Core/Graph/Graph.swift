import Foundation

/// The whole patch: every node plus every cable. Codable so it can be
/// snapshotted whole for undo/redo (same simple JSON-snapshot approach
/// Modula's PatchViewModel uses — not a diff-based undo stack).
struct Graph: Codable, Equatable {
    var nodes: [GraphNode]
    var connections: [GraphConnection]
    /// Performance knobs (see `Macro`) and their routes into node
    /// parameters (see `MacroAssignment`) — part of the graph, saved and
    /// undone right alongside its nodes and cables.
    var macros: [Macro] = []
    var macroAssignments: [MacroAssignment] = []

    static var empty: Graph { Graph(nodes: [], connections: []) }

    func node(_ id: UUID) -> GraphNode? {
        nodes.first { $0.id == id }
    }

    /// Texture-chain topological order ending at the Output node, used to
    /// build the render plan each frame. Nodes not reachable backward from
    /// Output are simply skipped (unpatched branches don't render, same as
    /// an unpatched Eurorack module producing no sound).
    func renderOrder() -> [GraphNode] {
        guard let output = nodes.first(where: { $0.kind == .output }) else { return [] }
        var visited = Set<UUID>()
        var order: [GraphNode] = []

        func visit(_ id: UUID) {
            guard !visited.contains(id), let node = self.node(id) else { return }
            visited.insert(id)
            let textureInputs = connections.filter { $0.destNodeID == id && $0.signalType == .texture }
            for connection in textureInputs {
                visit(connection.sourceNodeID)
            }
            order.append(node)
        }

        visit(output.id)
        return order
    }

    func textureSources(into nodeID: UUID) -> [String: UUID] {
        var result: [String: UUID] = [:]
        for connection in connections where connection.destNodeID == nodeID && connection.signalType == .texture {
            result[connection.destPortID] = connection.sourceNodeID
        }
        return result
    }

    /// The Input node (if any) whose value cable lands on this node's mod
    /// port — at most one, since every node exposes a single "mod" input.
    func modulationSource(for nodeID: UUID) -> GraphNode? {
        guard let connection = connections.first(where: { $0.destNodeID == nodeID && $0.destPortID == "mod" && $0.signalType == .value }) else {
            return nil
        }
        return node(connection.sourceNodeID)
    }
}
