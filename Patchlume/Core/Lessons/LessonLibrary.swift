import Foundation

/// The hand-written curriculum — short, hands-on lessons that each build a
/// real (if tiny) working graph, one node at a time, narrating what's
/// happening and why. Structure/pacing ported from Modula's
/// `LessonLibrary`; every word of content here is Patchlume-specific (node
/// graph concepts, not synth ones).
enum LessonLibrary {
    // `let`, not `var` — see the identical comment on GraphTemplateCatalog
    // for why: Lesson.id is a random UUID(), and a computed property would
    // regenerate it (and every Lesson below) on every access, churning row
    // identity in any view that re-renders often.
    static let all: [Lesson] =
        [firstGenerator, modifiersAndChains, audioReactivity, combiners, midiAndClock, cameraAndChromaKey]

    // MARK: - 1. Your First Generator

    private static let firstGenerator: Lesson = {
        Lesson(
            title: "Your First Generator",
            summary: "Add a generator, wire it to Output, see it live",
            icon: "sparkles",
            steps: [
                LessonStep(text: "Every Patchlume graph starts with a Generator — a node that produces a texture from scratch, with no input needed. Let's build the simplest possible graph: one Generator feeding straight into Output."),
                LessonStep(
                    text: "Adding a Plasma generator…",
                    buildActions: [
                        .addNode("gen", .generator, "plasma", caption: "This is Plasma — a generator that draws a live, drifting field of color from a few math functions. No inputs, no cables needed: it just runs."),
                        .addNode("out", .output, "output", caption: "Every graph needs exactly one Output node — it's the final composite you actually see in the preview at the top of the screen."),
                        .connect("gen", "out", "out", "in", caption: "Dragging a cable from the generator's \"out\" jack to Output's \"in\" jack completes the chain. The preview above is now live.")
                    ]
                ),
                LessonStep(text: "That's a complete, working graph — two nodes, one cable. Try turning the Complexity or Speed knob on the Plasma node and watch the preview change in real time.", highlightKind: .generator, highlightSubtype: "plasma")
            ]
        )
    }()

    // MARK: - 2. Modifiers & Chains

    private static let modifiersAndChains: Lesson = {
        Lesson(
            title: "Modifiers & Chains",
            summary: "Chain modifiers after a generator to reshape its texture",
            icon: "square.stack.3d.up",
            steps: [
                LessonStep(text: "A Modifier takes a texture in and hands a transformed texture out. Signal flows one way only: generator → modifier → modifier → … → output. You can chain as many modifiers as you like."),
                LessonStep(
                    text: "Building a Tunnel with two modifiers after it…",
                    buildActions: [
                        .addNode("gen", .generator, "tunnel", caption: "Tunnel — a generator that draws rings receding into the distance."),
                        .addNode("mirror", .modifier, "mirror", caption: "Mirror is a Modifier: it takes the Tunnel's texture in on its \"in\" jack and hands out a symmetrical version."),
                        .addNode("bloom", .modifier, "bloom", caption: "Bloom is another Modifier, chained right after Mirror — it adds a soft glow to whatever texture reaches it."),
                        .addNode("out", .output, "output"),
                        .connect("gen", "out", "mirror", "in", caption: "Tunnel's output feeds Mirror's input…"),
                        .connect("mirror", "out", "bloom", "in", caption: "…Mirror's output feeds Bloom's input…"),
                        .connect("bloom", "out", "out", "in", caption: "…and Bloom's output finally reaches Output. Three nodes, one straight chain.")
                    ]
                ),
                LessonStep(text: "Notice each modifier only ever has one texture flowing through it at a time — it transforms what it's given and passes it along. Try reordering: what happens if Bloom runs before Mirror instead?", highlightKind: .modifier)
            ]
        )
    }()

    // MARK: - 3. Wiring Audio Reactivity

    private static let audioReactivity: Lesson = {
        Lesson(
            title: "Wiring Audio Reactivity",
            summary: "Patch a Bass input into a generator's mod port",
            icon: "waveform",
            steps: [
                LessonStep(text: "Input nodes produce a live 0...1 value instead of a texture — Time, an LFO, or a live audio band like Bass, Mid, or Treble. Every generator and modifier exposes exactly one \"mod\" port: the single place an Input's cable can land, driving that node's most important parameter automatically."),
                LessonStep(
                    text: "Wiring Bass into Rings…",
                    buildActions: [
                        .addNode("gen", .generator, "rings", caption: "Rings — its first parameter, Density, is flagged as the primary modulation target, so it's the one the mod port drives."),
                        .addNode("out", .output, "output"),
                        .connect("gen", "out", "out", "in"),
                        .addNode("bass", .input, "bass", caption: "Bass is an Input node — it has no texture ports at all, just a single value \"out\" jack that follows the low end of whatever audio is playing."),
                        .connect("bass", "out", "gen", "mod", caption: "Dragging a cable from Bass's \"out\" to Rings' \"mod\" jack patches it straight into Density. Now the ring count pulses with the beat.")
                    ]
                ),
                LessonStep(text: "That's the whole pattern: pick any Input, drag it onto any node's single mod jack. It always targets that node's primary parameter — no need to pick which one.", highlightKind: .input, highlightSubtype: "bass")
            ]
        )
    }()

    // MARK: - 4. Combiners: Merging Two Branches

    private static let combiners: Lesson = {
        Lesson(
            title: "Combiners: Merging Two Branches",
            summary: "Build two generator branches and merge them with a Combiner",
            icon: "arrow.triangle.merge",
            steps: [
                LessonStep(text: "A Combiner is the one node type with two texture inputs — \"A\" and \"B\" — instead of one. It merges two independent branches into a single texture, then hands that on like any other node."),
                LessonStep(
                    text: "Building two branches and blending them…",
                    buildActions: [
                        .addNode("genA", .generator, "voronoi", caption: "Branch A: Voronoi Field, a cellular pattern."),
                        .addNode("genB", .generator, "starfield", caption: "Branch B: Starfield, streaking points of light — a completely independent texture, not connected to Voronoi at all."),
                        .addNode("blend", .combiner, "blend", caption: "Blend is a Combiner — its \"A\" jack takes one branch, its \"B\" jack takes the other."),
                        .addNode("out", .output, "output"),
                        .connect("genA", "out", "blend", "inA", caption: "Voronoi's output goes into Blend's \"A\" input…"),
                        .connect("genB", "out", "blend", "inB", caption: "…and Starfield's output goes into Blend's \"B\" input."),
                        .connect("blend", "out", "out", "in", caption: "Blend's single output — the two textures merged — reaches Output.")
                    ]
                ),
                LessonStep(text: "Try the Mode knob on the Blend node — Add, Screen, Multiply, and Mix each merge the two branches differently. Any combiner (Mask, Difference, Displace…) works the same way: two texture inputs in, one texture out.", highlightKind: .combiner, highlightSubtype: "blend")
            ]
        )
    }()

    // MARK: - 5. MIDI & Clock Control

    private static let midiAndClock: Lesson = {
        Lesson(
            title: "MIDI & Clock Control",
            summary: "Patch a MIDI CC input into a node's mod port",
            icon: "pianokeys",
            steps: [
                LessonStep(text: "Inputs aren't limited to audio bands — MIDI CC and MIDI Note read live from any connected MIDI controller, and Clock generates its own steady pulse from a BPM you set, no external gear required. Both patch into a mod port exactly like Bass or an LFO did."),
                LessonStep(
                    text: "Wiring a MIDI CC knob into Kaleidoscope…",
                    buildActions: [
                        .addNode("gen", .generator, "kaleido", caption: "Kaleidoscope — its Segments parameter is the primary modulation target."),
                        .addNode("out", .output, "output"),
                        .connect("gen", "out", "out", "in"),
                        .addNode("cc", .input, "midiCC", caption: "MIDI CC — set its CC Number knob to match a knob or fader on your controller, and its \"out\" value follows that controller in real time."),
                        .connect("cc", "out", "gen", "mod", caption: "Patched into Kaleidoscope's mod port — now a physical MIDI knob controls the segment count live.")
                    ]
                ),
                LessonStep(text: "Clock works the same way but needs no hardware at all — add a Clock Input, set its BPM and beat division, and wire it into any mod port for a rhythmic pulse instead of a smooth sweep. Try swapping the MIDI CC node above for a Clock node.", highlightKind: .input, highlightSubtype: "clock")
            ]
        )
    }()

    // MARK: - 6. Camera & Chroma Key

    private static let cameraAndChromaKey: Lesson = {
        Lesson(
            title: "Camera & Chroma Key",
            summary: "Feed a live camera image through Chroma Key",
            icon: "camera.fill",
            steps: [
                LessonStep(text: "Camera is the one Generator that isn't procedural — instead of drawing a pattern from math, it feeds in your device's live camera image as a texture, which you can then run through any modifier chain just like a generated one."),
                LessonStep(
                    text: "Building a Camera + Chroma Key chain…",
                    buildActions: [
                        .addNode("cam", .generator, "camera", caption: "Camera — Patchlume will ask for camera permission the first time a graph like this one actually runs."),
                        .addNode("key", .modifier, "chromaKey", caption: "Chroma Key is a Modifier built specifically for camera input — it makes pixels near a target color transparent, the classic green-screen technique."),
                        .addNode("out", .output, "output"),
                        .connect("cam", "out", "key", "in", caption: "Camera's live texture flows into Chroma Key…"),
                        .connect("key", "out", "out", "in", caption: "…and the keyed result reaches Output.")
                    ]
                ),
                LessonStep(text: "Adjust Chroma Key's Threshold and Softness to key out a solid background color, then chain more modifiers after it — Twirl, Datamosh, or Posterize all work well on camera footage. This is the only generator where the camera engine actually turns on.", highlightKind: .generator, highlightSubtype: "camera")
            ]
        )
    }()
}
