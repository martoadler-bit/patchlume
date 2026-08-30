import Foundation

/// The hand-written challenge set — each one a small, concrete task checked
/// live against the graph the player builds on a blank canvas. Structure
/// ported from Modula's `ChallengeLibrary`; the checks themselves are new,
/// since Patchlume can inspect its own graph structure directly instead of
/// only comparing module-kind counts against a hidden target. Each also
/// carries a `hint` and a `solution` (see `Challenge.swift`) so a stuck
/// player has somewhere to go besides guessing.
enum ChallengeLibrary {
    // `let`, not `var` — same reason as GraphTemplateCatalog/LessonLibrary:
    // Challenge.id is a random UUID(), and a computed property would
    // regenerate every Challenge (and its id) on every access.
    static let all: [Challenge] =
        [addAnyGenerator, reachOutput, chainThreeModifiers, mergeWithCombiner,
         wireAudioReactivity, addMIDIInput, feedbackInTheChain, hideAllCables]

    private static let addAnyGenerator: Challenge = Challenge(
        title: "Add a Generator", summary: "Place any Generator node on the canvas.", icon: "sparkles",
        hint: "Tap the + button and add any Generator — Plasma is a good one to start with.",
        solution: [
            .addNode("gen", .generator, "plasma", caption: "Adding a Plasma generator — that alone satisfies this one.")
        ]
    ) { store in
        store.nodes.contains { $0.kind == .generator }
    }

    private static let reachOutput: Challenge = Challenge(
        title: "Reach the Output", summary: "Connect a Generator through to the Output node.", icon: "arrow.right.to.line",
        hint: "Add a Generator, then drag a cable from its \"out\" jack to the Output node's \"in\" jack.",
        solution: [
            .addNode("gen", .generator, "rings", caption: "Add a generator…"),
            .addNode("out", .output, "output", caption: "…and an Output node."),
            .connect("gen", "out", "out", "in", caption: "Connect them — the chain now reaches Output.")
        ]
    ) { store in
        store.graph.renderOrder().contains { $0.kind == .generator }
    }

    private static let chainThreeModifiers: Challenge = {
        Challenge(
            title: "Chain Three Modifiers", summary: "Build a chain of at least three Modifiers in a row.", icon: "square.stack.3d.up",
            hint: "Add three Modifiers in a row — each one's \"in\" jack connected to the previous one's \"out\".",
            solution: [
                .addNode("gen", .generator, "voronoi", caption: "Start with a generator…"),
                .addNode("m1", .modifier, "blur", caption: "…first modifier…"),
                .addNode("m2", .modifier, "hueRotate", caption: "…second…"),
                .addNode("m3", .modifier, "bloom", caption: "…third — three in a row."),
                .connect("gen", "out", "m1", "in"),
                .connect("m1", "out", "m2", "in"),
                .connect("m2", "out", "m3", "in"),
                .addNode("out", .output, "output"),
                .connect("m3", "out", "out", "in", caption: "Wired through to Output — done.")
            ]
        ) { store in
            let graph = store.graph
            // A modifier whose "in" texture source is itself a modifier
            // whose "in" texture source is a third modifier — three deep.
            for node in graph.nodes where node.kind == .modifier {
                guard let secondID = graph.textureSources(into: node.id)["in"],
                      let second = graph.node(secondID), second.kind == .modifier else { continue }
                guard let thirdID = graph.textureSources(into: second.id)["in"],
                      let third = graph.node(thirdID), third.kind == .modifier else { continue }
                return true
            }
            return false
        }
    }()

    private static let mergeWithCombiner: Challenge = Challenge(
        title: "Merge Two Generators", summary: "Use a Combiner to merge two Generator branches.", icon: "arrow.triangle.merge",
        hint: "Add two Generators and a Combiner (like Blend), then wire one generator into \"A\" and the other into \"B\".",
        solution: [
            .addNode("a", .generator, "plasma", caption: "Branch A…"),
            .addNode("b", .generator, "kaleido", caption: "…branch B — independent of each other."),
            .addNode("comb", .combiner, "blend", caption: "A Combiner takes two texture inputs…"),
            .connect("a", "out", "comb", "inA"),
            .connect("b", "out", "comb", "inB", caption: "…both branches feeding in."),
            .addNode("out", .output, "output"),
            .connect("comb", "out", "out", "in", caption: "Merged result reaching Output — done.")
        ]
    ) { store in
        let graph = store.graph
        for node in graph.nodes where node.kind == .combiner {
            let sources = graph.textureSources(into: node.id)
            guard let aID = sources["inA"], let bID = sources["inB"] else { continue }
            if graph.node(aID)?.kind == .generator && graph.node(bID)?.kind == .generator {
                return true
            }
        }
        return false
    }

    private static let wireAudioReactivity: Challenge = {
        let audioBands: Set<String> = ["bass", "mid", "treble", "energy", "beatStrength"]
        return Challenge(
            title: "Wire in Audio Reactivity", summary: "Patch an audio Input into any node's mod port.", icon: "waveform",
            hint: "Add an audio Input (Bass, Mid, Treble, Energy, or Beat Strength) and drag its cable onto any node's \"mod\" jack.",
            solution: [
                .addNode("gen", .generator, "rings", caption: "A generator to modulate…"),
                .addNode("bass", .input, "bass", caption: "…and Bass, a live audio Input."),
                .connect("bass", "out", "gen", "mod", caption: "Patched into the mod port — done."),
                .addNode("out", .output, "output"),
                .connect("gen", "out", "out", "in")
            ]
        ) { store in
            store.graph.connections.contains { connection in
                connection.destPortID == "mod" &&
                store.node(connection.sourceNodeID)?.kind == .input &&
                audioBands.contains(store.node(connection.sourceNodeID)?.subtype ?? "")
            }
        }
    }()

    private static let addMIDIInput: Challenge = Challenge(
        title: "Add a MIDI Input", summary: "Place a MIDI CC or MIDI Note input node.", icon: "pianokeys",
        hint: "Add either a MIDI CC or MIDI Note input node from the library — no cable needed to complete this one.",
        solution: [
            .addNode("cc", .input, "midiCC", caption: "A MIDI CC input node — that alone satisfies it.")
        ]
    ) { store in
        store.nodes.contains { $0.kind == .input && ($0.subtype == "midiCC" || $0.subtype == "midiNote") }
    }

    private static let feedbackInTheChain: Challenge = Challenge(
        title: "Feedback Trails", summary: "Get a Feedback modifier somewhere in the chain that reaches Output.", icon: "arrow.3.trianglepath",
        hint: "Add a Feedback modifier between a Generator and the Output node.",
        solution: [
            .addNode("gen", .generator, "plasma", caption: "A generator…"),
            .addNode("fb", .modifier, "feedback", caption: "…and a Feedback modifier."),
            .addNode("out", .output, "output"),
            .connect("gen", "out", "fb", "in"),
            .connect("fb", "out", "out", "in", caption: "In the chain that reaches Output — done.")
        ]
    ) { store in
        store.graph.renderOrder().contains { $0.kind == .modifier && $0.subtype == "feedback" }
    }

    private static let hideAllCables: Challenge = Challenge(
        title: "Declutter the Canvas", summary: "Hide all cables using the canvas toggle in the menu.", icon: "eye.slash",
        hint: "Open the \"...\" menu at the top and tap \"Hide Cables\" — nothing to build for this one.",
        solution: []
    ) { store in
        store.cablesHidden
    }
}
