import Foundation

/// Turns any `Graph` into a `Lesson` on the fly: one step per node, in
/// signal-flow order, highlighting it and explaining what it does plus
/// where its output goes — generated from the graph's own connections
/// rather than hand-written, so every template gets a tour for free instead
/// of needing its own scripted content. Ported from Modula's
/// `PatchTourBuilder` (Module -> Node, Patch -> Graph), reusing `Graph`'s
/// own `renderOrder()` topological sort instead of re-implementing Kahn's
/// algorithm since the render pipeline already needs one.
enum GraphTourBuilder {
    static func tour(name: String, for graph: Graph) -> Lesson {
        // renderOrder() only walks nodes reachable backward from Output, so
        // dangling/unconnected nodes (rare, but possible in a hand-edited
        // graph) are appended afterward to keep the tour complete.
        var ordered = graph.renderOrder()
        let coveredIDs = Set(ordered.map(\.id))
        ordered.append(contentsOf: graph.nodes.filter { !coveredIDs.contains($0.id) })

        var steps: [LessonStep] = [
            LessonStep(
                text: "A tour of \"\(name)\" — \(graph.nodes.count) nodes, in signal-flow order. Tap Next to follow the signal from source to output.",
                graphToLoad: graph
            )
        ]

        for node in ordered {
            let destinationKinds = graph.connections
                .filter { $0.sourceNodeID == node.id }
                .compactMap { connection in graph.node(connection.destNodeID)?.kind }
            let uniqueDestinationNames = Array(Set(destinationKinds)).map(displayName(for:)).sorted()

            var text = "\(NodeCatalog.displayName(kind: node.kind, subtype: node.subtype)): \(shortDescription(kind: node.kind, subtype: node.subtype))"
            if !uniqueDestinationNames.isEmpty {
                text += " Its output feeds into the \(uniqueDestinationNames.joined(separator: " and "))."
            }

            steps.append(LessonStep(text: text, highlightKind: node.kind, highlightSubtype: node.subtype, highlightNodeID: node.id))
        }

        steps.append(LessonStep(
            text: "That's the whole signal path. Feel free to explore from here — drag a knob, hold down a jack to disconnect its cable, or wire something new."
        ))

        return Lesson(title: name, summary: "A guided tour of this template", icon: "info.circle", steps: steps)
    }

    private static func displayName(for kind: NodeKind) -> String {
        switch kind {
        case .generator: return "Generator"
        case .modifier: return "Modifier"
        case .combiner: return "Combiner"
        case .input: return "Input"
        case .output: return "Output"
        }
    }

    /// One generic sentence per node kind — same "framework-level, not
    /// per-subtype" idea as Modula's `ModuleCatalog.shortDescription`, so
    /// adding a new generator/modifier never requires touching this file.
    private static func shortDescription(kind: NodeKind, subtype: String) -> String {
        switch kind {
        case .generator: return "Produces a live texture from scratch — the start of a signal chain."
        case .modifier: return "Transforms the texture that flows into it before passing it on."
        case .combiner: return "Merges two texture branches into one."
        case .input: return "Produces a live 0...1 value you can patch into a node's mod port."
        case .output: return "The final composite shown in the preview."
        }
    }
}
