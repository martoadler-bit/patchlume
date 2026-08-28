import CoreGraphics
import Foundation

/// Ready-made starter graphs — a factory-preset library, same role as
/// Modula's `FactoryPresets`: pick one, it's already alive, tweak from
/// there. Grouped simple -> complex so a first-time user isn't dropped on
/// a 12-node patch, and a curious one has somewhere to grow into.
enum GraphTemplateCatalog {
    struct Template: Identifiable {
        let id = UUID()
        let name: String
        let category: String
        let make: () -> Graph
    }

    // `all`/`categories`/every category group below are STORED (`let`), not
    // computed (`var`) properties — deliberately. `Template.id` is a random
    // `UUID()` generated when each `Template` value is constructed; as a
    // computed property, `all` (and everything under it) used to
    // re-construct every Template — with a brand-new random id — on EVERY
    // access, including every SwiftUI body re-evaluation. TemplateBrowserView
    // reads `viewModel` (an `@EnvironmentObject`), which republishes
    // continuously (it bridges the audio engine's own frequent republishing),
    // so its body — and this whole tree — was re-evaluating many times a
    // second, handing `ForEach` a fresh set of row identities on every
    // re-render. SwiftUI ties in-flight gesture recognition to a row's
    // identity; when the identity churns out from under a tap mid-gesture,
    // the row shows its press/highlight state but the tap never completes —
    // which is exactly the "highlights, does nothing" symptom, on every
    // single tap, regardless of how the row's Button/gesture was structured.
    // A `let` is built once and reused, so every Template keeps the same id
    // for the life of the app.
    static let all: [Template] = basics + audioReactive + midi + combined + flagship + newModules + performance

    static let categories: [String] =
        ["Basics", "Audio Reactive", "MIDI", "Combiners", "Flagship", "New Modules", "Performance"]

    static func templates(in category: String) -> [Template] {
        all.filter { $0.category == category }
    }

    /// The graph shown on first launch — never a black screen.
    static func starter() -> Graph { bassPulseRings.make() }

    // MARK: - Basics (no audio/MIDI wiring — pure generator behavior)

    private static let basics: [Template] = {
        [
            Template(name: "Pure Plasma", category: "Basics") {
                build(branchA: [Step("plasma")])
            },
            Template(name: "Ring Pulse", category: "Basics") {
                build(branchA: [Step("rings")], mods: [ModWire(input: "lfo", targetIndex: 0)])
            },
            Template(name: "Kaleido Drift", category: "Basics") {
                build(branchA: [Step("kaleido")], mods: [ModWire(input: "lfo", targetIndex: 0)])
            },
            Template(name: "Starfield Cruise", category: "Basics") {
                build(branchA: [Step("starfield")], mods: [ModWire(input: "lfo", targetIndex: 0)])
            },
            bassPulseRings,
        ]
    }()

    private static let bassPulseRings: Template = Template(name: "Bass Pulse Rings", category: "Basics") {
        build(branchA: [Step("rings"), Step("hueRotate")], mods: [ModWire(input: "bass", targetIndex: 0)])
    }

    // MARK: - Audio Reactive (one audio-band input driving the chain)

    private static let audioReactive: [Template] = {
        [
            Template(name: "Treble Sparkle", category: "Audio Reactive") {
                build(branchA: [Step("starfield"), Step("bloom")], mods: [ModWire(input: "treble", targetIndex: 0)],
                      macros: [MacroSpec("Sparkle", routes: [
                          (0, "p2", 0, 1.5),      // Starfield Streak [0...2]
                          (1, "p0", 0.2, 0.9)])]) // Bloom Threshold [0...1]
            },
            Template(name: "Mid Voronoi Cells", category: "Audio Reactive") {
                build(branchA: [Step("voronoi"), Step("blur")], mods: [ModWire(input: "mid", targetIndex: 0)],
                      macros: [MacroSpec("Cells", routes: [
                          (0, "p2", 1, 6),       // Voronoi Edge Sharpness [0.5...8]
                          (1, "p0", 0, 0.7)])]) // Blur Amount [0...1]
            },
            Template(name: "Energy Kaleidoscope", category: "Audio Reactive") {
                build(branchA: [Step("kaleido"), Step("hueRotate"), Step("bloom")],
                      mods: [ModWire(input: "energy", targetIndex: 0), ModWire(input: "beatStrength", targetIndex: 1)],
                      macros: [MacroSpec("Vibe", routes: [
                          (0, "p2", 0.3, 2.5),    // Kaleido Zoom [0.2...4]
                          (2, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Glitch Pulse", category: "Audio Reactive") {
                build(branchA: [Step("voronoi"), Step("rgbSplit"), Step("scanlines")],
                      mods: [ModWire(input: "beatStrength", targetIndex: 1)],
                      macros: [MacroSpec("Glitch", routes: [
                          (1, "p0", 0, 0.08),   // RGB Split Amount [0...0.1]
                          (2, "p1", 0, 0.8)])]) // Scanlines Intensity [0...1]
            },
            Template(name: "Grid Pulse Machine", category: "Audio Reactive") {
                build(branchA: [Step("gridPulse"), Step("pixelate")], mods: [ModWire(input: "beatStrength", targetIndex: 0)],
                      macros: [MacroSpec("Chunk", routes: [
                          (0, "p2", 4, 30),    // Grid Size [2...40]
                          (1, "p0", 2, 40)])]) // Pixelate Cell Size [1...64]
            },
            Template(name: "Gradient Wash", category: "Audio Reactive") {
                build(branchA: [Step("gradientFlow"), Step("blur"), Step("hueRotate")],
                      mods: [ModWire(input: "energy", targetIndex: 0)],
                      macros: [MacroSpec("Wash", routes: [
                          (0, "p2", 1, 4),   // Gradient Flow Scale [0.5...6]
                          (2, "p0", 0, 1)])]) // Hue Rotation [0...1]
            },
            Template(name: "Feedback Trails", category: "Audio Reactive") {
                build(branchA: [Step("plasma"), Step("feedback")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "bass", targetIndex: 1)],
                      macros: [MacroSpec("Echo", routes: [
                          (0, "p2", 1, 4),         // Plasma Scale [0.5...6]
                          (1, "p1", 0.95, 1.05)])]) // Feedback Zoom [0.9...1.1]
            },
            Template(name: "Neon Tunnel", category: "Audio Reactive") {
                build(branchA: [Step("tunnel"), Step("mirror"), Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0)],
                      macros: [MacroSpec("Neon", routes: [
                          (0, "p1", 0, 4),       // Tunnel Twist [0...6]
                          (2, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
        ]
    }()

    // MARK: - MIDI (CC / Note driven)

    private static let midi: [Template] = {
        [
            Template(name: "MIDI CC Tunnel", category: "MIDI") {
                build(branchA: [Step("tunnel"), Step("scanlines")], mods: [ModWire(input: "midiCC", targetIndex: 0)],
                      macros: [MacroSpec("Depth", routes: [
                          (0, "p2", 4, 30),    // Tunnel Rings [2...40]
                          (1, "p1", 0, 0.7)])]) // Scanlines Intensity [0...1]
            },
            Template(name: "MIDI Note Rings", category: "MIDI") {
                build(branchA: [Step("rings"), Step("hueRotate")], mods: [ModWire(input: "midiNote", targetIndex: 0)],
                      macros: [MacroSpec("Glow", routes: [
                          (0, "p2", 0.05, 0.35), // Rings Thickness [0.02...0.5]
                          (1, "p1", 0.5, 2)])])  // Hue Rotate Saturation [0...2]
            },
            Template(name: "MIDI Kaleido Rig", category: "MIDI") {
                build(branchA: [Step("kaleido"), Step("rgbSplit"), Step("bloom")],
                      mods: [ModWire(input: "midiCC", targetIndex: 0), ModWire(input: "midiNote", targetIndex: 1)],
                      macros: [MacroSpec("Rig", routes: [
                          (0, "p2", 0.3, 2.5),    // Kaleido Zoom [0.2...4]
                          (2, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
        ]
    }()

    // MARK: - Combiners (two generator branches merged)

    private static let combined: [Template] = {
        [
            Template(name: "Twin Tunnel Blend", category: "Combiners") {
                build(branchA: [Step("tunnel")], branchB: [Step("rings")], combinerType: "blend",
                      combinerOverrides: ["p1": 3],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "bass", targetIndex: 1)],
                      macros: [MacroSpec("Blend", routes: [(2, "p0", 0, 1)])]) // Blend Mix [0...1]
            },
            Template(name: "Voronoi Mask", category: "Combiners") {
                build(branchA: [Step("voronoi")], branchB: [Step("starfield")], combinerType: "mask",
                      mods: [ModWire(input: "mid", targetIndex: 0)],
                      macros: [MacroSpec("Reveal", routes: [(2, "p0", 0.2, 0.8)])]) // Mask Threshold [0...1]
            },
            Template(name: "Difference Storm", category: "Combiners") {
                build(branchA: [Step("plasma")], branchB: [Step("kaleido")], combinerType: "difference",
                      post: [Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "energy", targetIndex: 1)],
                      macros: [MacroSpec("Storm", routes: [
                          (2, "p0", 0.3, 1),      // Difference Amount [0...1]
                          (3, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Layered Pulse", category: "Combiners") {
                build(branchA: [Step("gridPulse")], branchB: [Step("rings")], combinerType: "blend",
                      combinerOverrides: ["p1": 1], post: [Step("bloom")],
                      mods: [ModWire(input: "beatStrength", targetIndex: 0), ModWire(input: "bass", targetIndex: 1)],
                      macros: [MacroSpec("Layers", routes: [
                          (2, "p0", 0, 1),        // Blend Mix [0...1]
                          (3, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
        ]
    }()

    // MARK: - Flagship (many nodes, several modulation wires, shows the ceiling)

    private static let flagship: [Template] = {
        [
            Template(name: "Night Drive", category: "Flagship") {
                build(branchA: [Step("tunnel"), Step("mirror"), Step("rgbSplit"), Step("scanlines"), Step("bloom")],
                      mods: [ModWire(input: "bass", targetIndex: 0), ModWire(input: "beatStrength", targetIndex: 2),
                             ModWire(input: "treble", targetIndex: 4)],
                      macros: [MacroSpec("Drive", routes: [
                          (2, "p0", 0, 0.08),     // RGB Split Amount [0...0.1]
                          (4, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Cosmic Cascade", category: "Flagship") {
                build(branchA: [Step("starfield")], branchB: [Step("kaleido")], combinerType: "blend",
                      combinerOverrides: ["p1": 3],
                      post: [Step("hueRotate"), Step("bloom"), Step("feedback")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "energy", targetIndex: 1),
                             ModWire(input: "beatStrength", targetIndex: 4)],
                      macros: [MacroSpec("Cosmic", routes: [
                          (2, "p0", 0, 1),          // Blend Mix [0...1]
                          (4, "p1", 0.3, 2.5),      // Bloom Intensity [0...3]
                          (5, "p0", 0.5, 0.95)])]) // Feedback Decay [0...0.98]
            },
            Template(name: "MIDI Reactive Rig", category: "Flagship") {
                build(branchA: [Step("rings")], branchB: [Step("voronoi")], combinerType: "mask",
                      post: [Step("scanlines"), Step("bloom")],
                      mods: [ModWire(input: "midiCC", targetIndex: 0), ModWire(input: "midiNote", targetIndex: 1)],
                      macros: [MacroSpec("Reactive", routes: [
                          (2, "p0", 0.2, 0.8),    // Mask Threshold [0...1]
                          (4, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Signal Storm", category: "Flagship") {
                build(branchA: [Step("plasma"), Step("hueRotate")], branchB: [Step("gridPulse"), Step("pixelate")],
                      combinerType: "difference", post: [Step("rgbSplit"), Step("bloom")],
                      mods: [ModWire(input: "mid", targetIndex: 0), ModWire(input: "beatStrength", targetIndex: 2),
                             ModWire(input: "treble", targetIndex: 5)],
                      macros: [MacroSpec("Storm", routes: [
                          (4, "p0", 0.3, 1),      // Difference Amount [0...1]
                          (6, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Deep Feedback Wash", category: "Flagship") {
                build(branchA: [Step("gradientFlow"), Step("blur"), Step("feedback"), Step("hueRotate")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "energy", targetIndex: 1),
                             ModWire(input: "bass", targetIndex: 2)],
                      macros: [MacroSpec("Depth", routes: [
                          (2, "p0", 0.5, 0.95),  // Feedback Decay [0...0.98]
                          (0, "p2", 1, 4)])])   // Gradient Flow Scale [0.5...6]
            },
            Template(name: "Grand Finale", category: "Flagship") {
                build(branchA: [Step("camera"), Step("chromaKey"),
                                Step("twirl", inlineLFO: (paramID: "p0", rate: 0.15, depth: 0.5, shape: 0))],
                      branchB: [Step("fractal", ["p2": 0]), Step("posterize")],
                      combinerType: "displace",
                      post: [Step("bloom"), Step("vignette"),
                             Step("feedback", inlineLFO: (paramID: "p0", rate: 0.1, depth: 0.3, shape: 0))],
                      mods: [ModWire(input: "noise", targetIndex: 3)],
                      macros: [MacroSpec("Performance", routes: [
                          (2, "p0", -2, 2),      // Twirl Strength [-3...3]
                          (4, "p0", 3, 12),       // Posterize Levels [2...16]
                          (6, "p1", 0.2, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Orbital Drift", category: "Flagship") {
                build(branchA: [Step("particles")], branchB: [Step("reaction")], combinerType: "lumaKey",
                      post: [Step("hueRotate"), Step("bloom")],
                      mods: [ModWire(input: "beatStrength", targetIndex: 0), ModWire(input: "bass", targetIndex: 1)],
                      macros: [MacroSpec("Drift", routes: [
                          (0, "p0", 10, 140),   // Particles Count [4...160]
                          (1, "p0", 0.2, 1.8)])]) // Reaction Growth [0...2]
            },
        ]
    }()

    // MARK: - Performance (Macros + inline per-parameter LFO showcase — one
    // knob or one long-press moving several parameters at once, the payoff
    // of the modulation system generalizing past the single cable-based
    // "mod" port)

    private static let performance: [Template] = {
        [
            Template(name: "Breathing Rings", category: "Performance") {
                build(branchA: [Step("rings", inlineLFO: (paramID: "p2", rate: 0.3, depth: 0.6, shape: 0)), Step("bloom")])
            },
            Template(name: "Macro Morph", category: "Performance") {
                build(branchA: [Step("plasma"), Step("hueRotate"), Step("bloom")],
                      macros: [MacroSpec("Morph", routes: [
                          (0, "p0", 2, 7),       // Plasma Complexity [1...8]
                          (1, "p0", 0, 1),        // Hue Rotate Rotation [0...1]
                          (2, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Twin Macro Rig", category: "Performance") {
                build(branchA: [Step("voronoi")], branchB: [Step("starfield")], combinerType: "blend",
                      post: [Step("bloom")],
                      macros: [MacroSpec("Mix", routes: [(2, "p0", 0, 1)]),        // Blend Mix [0...1]
                               MacroSpec("Chaos", routes: [
                                   (0, "p0", 5, 25),    // Voronoi Cell Count [2...30]
                                   (1, "p0", 0.5, 6)])]) // Starfield Speed [0...8]
            },
            Template(name: "Triple Threat", category: "Performance") {
                build(branchA: [Step("tunnel", inlineLFO: (paramID: "p1", rate: 0.4, depth: 0.5, shape: 1)),
                                Step("mirror"),
                                Step("rgbSplit", inlineLFO: (paramID: "p1", rate: 0.2, depth: 1.0, shape: 3)),
                                Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0)],
                      macros: [MacroSpec("Intensity", routes: [
                          (3, "p1", 0.2, 2.8),  // Bloom Intensity [0...3]
                          (1, "p1", -0.8, 0.8)])]) // Mirror Offset [-1...1]
            },
            // 8 macros, one clear single-purpose fader each — the max
            // Performance Mode/the Macro remote show at once, meant to
            // stress-test that whole bank rather than showcase any one
            // routing trick.
            Template(name: "VJ Rig — 8 Faders", category: "Performance") {
                build(branchA: [Step("camera"), Step("chromaKey"), Step("twirl")],
                      branchB: [Step("fractal", ["p2": 0]), Step("posterize")],
                      combinerType: "displace",
                      post: [Step("bloom"), Step("vignette"), Step("feedback")],
                      macros: [
                          MacroSpec("Exposure", routes: [(0, "p0", 0.3, 1.8)]),   // Camera Exposure [0.2...2]
                          MacroSpec("Key", routes: [(1, "p0", 0.1, 0.7)]),        // Chroma Key Threshold [0...1]
                          MacroSpec("Twirl", routes: [(2, "p0", -2.5, 2.5)]),     // Twirl Strength [-3...3]
                          MacroSpec("Zoom", routes: [(3, "p0", 0.5, 6)]),         // Fractal Zoom [0.3...8]
                          MacroSpec("Posterize", routes: [(4, "p0", 2, 14)]),     // Posterize Levels [2...16]
                          MacroSpec("Displace", routes: [(5, "p0", 0, 1)]),       // Displace Amount [0...1]
                          MacroSpec("Bloom", routes: [(6, "p1", 0.2, 2.8)]),      // Bloom Intensity [0...3]
                          MacroSpec("Feedback", routes: [(8, "p0", 0, 0.9)]),     // Feedback Decay [0...0.98]
                      ])
            },
            // 6 macros with a mix of single- and multi-target routes, on a
            // simpler underlying graph than "VJ Rig" — a second, lighter
            // Performance Mode test case.
            Template(name: "Six Pack", category: "Performance") {
                build(branchA: [Step("gridPulse"), Step("scanlines")],
                      branchB: [Step("kaleido"), Step("hueRotate")],
                      combinerType: "blend",
                      post: [Step("bloom")],
                      macros: [
                          MacroSpec("Pulse", routes: [(0, "p0", 0.3, 3.5)]),          // Grid Pulse Amount [0...4]
                          MacroSpec("Scan", routes: [(1, "p1", 0, 0.9)]),             // Scanlines Intensity [0...1]
                          MacroSpec("Segments", routes: [(2, "p0", 3, 20)]),          // Kaleido Segments [2...24]
                          MacroSpec("Hue", routes: [(3, "p0", 0, 1)]),                // Hue Rotate Rotation [0...1]
                          MacroSpec("Mix", routes: [(4, "p0", 0, 1), (5, "p1", 0.3, 2.5)]), // Blend Mix + Bloom Intensity together
                          MacroSpec("Speed", routes: [(0, "p1", 0.3, 3), (2, "p1", 0.3, 2.5)]), // Grid + Kaleido speed together
                      ])
            },
        ]
    }()

    // MARK: - New Modules (one preset per newly added generator/modifier/
    // combiner/input, so nothing shipped without a working example to open)

    private static let newModules: [Template] = {
        [
            Template(name: "Fractal Zoom", category: "New Modules") {
                build(branchA: [Step("fractal", ["p2": 0]), Step("bloom")],
                      mods: [ModWire(input: "envelope", targetIndex: 0)],
                      macros: [MacroSpec("Zoom", routes: [
                          (0, "p0", 0.5, 4),      // Fractal Zoom [0.3...8]
                          (1, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Julia Drift", category: "New Modules") {
                build(branchA: [Step("fractal", ["p2": 1]), Step("hueRotate")],
                      mods: [ModWire(input: "noise", targetIndex: 0)],
                      macros: [MacroSpec("Julia", routes: [
                          (0, "p1", 0.5, 2.5), // Fractal Detail [0.3...3]
                          (1, "p0", 0, 1)])])  // Hue Rotation [0...1]
            },
            Template(name: "Reaction Bloom", category: "New Modules") {
                build(branchA: [Step("reaction"), Step("bloom")], mods: [ModWire(input: "bass", targetIndex: 0)],
                      macros: [MacroSpec("Grow", routes: [
                          (0, "p0", 0.3, 1.8),    // Reaction Growth [0...2]
                          (1, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Matrix Cascade", category: "New Modules") {
                build(branchA: [Step("matrixRain"), Step("scanlines")], mods: [ModWire(input: "clock", targetIndex: 0)],
                      macros: [MacroSpec("Cascade", routes: [
                          (0, "p1", 15, 60),   // Matrix Rain Density [10...80]
                          (1, "p1", 0, 0.7)])]) // Scanlines Intensity [0...1]
            },
            Template(name: "Particle Storm", category: "New Modules") {
                build(branchA: [Step("particles"), Step("bloom")], mods: [ModWire(input: "beatStrength", targetIndex: 0)],
                      macros: [MacroSpec("Storm", routes: [
                          (0, "p2", 0.3, 1.8),    // Particles Size [0.1...2]
                          (1, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Camera Chroma Twirl", category: "New Modules") {
                build(branchA: [Step("camera"), Step("chromaKey"), Step("twirl")],
                      mods: [ModWire(input: "envelope", targetIndex: 2)],
                      macros: [MacroSpec("Twirl", routes: [
                          (1, "p0", 0.1, 0.7),     // Chroma Key Threshold [0...1]
                          (2, "p0", -2.5, 2.5)])]) // Twirl Strength [-3...3]
            },
            Template(name: "Camera Datamosh", category: "New Modules") {
                build(branchA: [Step("camera"), Step("datamosh"), Step("posterize")],
                      mods: [ModWire(input: "sampleHold", targetIndex: 1)],
                      macros: [MacroSpec("Mosh", routes: [
                          (1, "p0", 0.1, 0.8),  // Datamosh Amount [0...1]
                          (2, "p0", 2, 12)])])  // Posterize Levels [2...16]
            },
            Template(name: "Edge Sketch", category: "New Modules") {
                build(branchA: [Step("voronoi"), Step("edgeDetect")], mods: [ModWire(input: "mid", targetIndex: 1)],
                      macros: [MacroSpec("Sketch", routes: [
                          (0, "p2", 1, 6),      // Voronoi Edge Sharpness [0.5...8]
                          (1, "p0", 0.1, 0.6)])]) // Edge Detect Threshold [0...1]
            },
            Template(name: "Vignette Noir", category: "New Modules") {
                build(branchA: [Step("starfield"), Step("vignette"), Step("posterize")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "treble", targetIndex: 1)],
                      macros: [MacroSpec("Noir", routes: [
                          (1, "p0", 0.2, 0.9),  // Vignette Amount [0...1]
                          (2, "p0", 2, 10)])])  // Posterize Levels [2...16]
            },
            Template(name: "Displace Flow", category: "New Modules") {
                build(branchA: [Step("gradientFlow")], branchB: [Step("plasma")], combinerType: "displace",
                      post: [Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "sampleHold", targetIndex: 1)],
                      macros: [MacroSpec("Flow", routes: [
                          (2, "p0", 0.2, 0.9),    // Displace Amount [0...1]
                          (3, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Luma Composite", category: "New Modules") {
                build(branchA: [Step("camera")], branchB: [Step("kaleido")], combinerType: "lumaKey",
                      mods: [ModWire(input: "envelope", targetIndex: 1)],
                      macros: [MacroSpec("Composite", routes: [(2, "p0", 0.2, 0.8)])]) // Luma Key Threshold [0...1]
            },
            Template(name: "Beat Crossfade Mix", category: "New Modules") {
                build(branchA: [Step("tunnel")], branchB: [Step("rings")], combinerType: "beatCrossfade",
                      post: [Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "bass", targetIndex: 1)],
                      macros: [MacroSpec("Crossfade", routes: [
                          (2, "p1", 0.1, 0.6),    // Beat Crossfade Softness [0...1]
                          (3, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Clocked Grid", category: "New Modules") {
                build(branchA: [Step("gridPulse"), Step("posterize")], mods: [ModWire(input: "clock", targetIndex: 0)],
                      macros: [MacroSpec("Clock", routes: [
                          (0, "p2", 4, 30),   // Grid Size [2...40]
                          (1, "p0", 2, 12)])]) // Posterize Levels [2...16]
            },
            Template(name: "Noise Drift Field", category: "New Modules") {
                build(branchA: [Step("gradientFlow"), Step("twirl")],
                      mods: [ModWire(input: "noise", targetIndex: 0), ModWire(input: "envelope", targetIndex: 1)],
                      macros: [MacroSpec("Drift", routes: [
                          (0, "p2", 1, 4),        // Gradient Flow Scale [0.5...6]
                          (1, "p0", -2.5, 2.5)])]) // Twirl Strength [-3...3]
            },
            Template(name: "Flow Field Threads", category: "New Modules") {
                build(branchA: [Step("flowField"), Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "bass", targetIndex: 1)],
                      macros: [MacroSpec("Threads", routes: [
                          (0, "p2", 0.3, 2.5),    // Flow Field Turbulence [0...3]
                          (1, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Line Art Sketch", category: "New Modules") {
                build(branchA: [Step("lineArt"), Step("vignette")],
                      mods: [ModWire(input: "mid", targetIndex: 0)],
                      macros: [MacroSpec("Sketch", routes: [
                          (0, "p2", 0.2, 1.5),   // Line Art Wobble [0...2]
                          (1, "p0", 0.2, 0.8)])]) // Vignette Amount [0...1]
            },
            Template(name: "Trail Blaze", category: "New Modules") {
                build(branchA: [Step("plasma"), Step("trails")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "beatStrength", targetIndex: 1)],
                      macros: [MacroSpec("Blaze", routes: [
                          (0, "p2", 1, 4),      // Plasma Scale [0.5...6]
                          (1, "p1", 0.4, 1)])])  // Trails Amount [0...1]
            },
            Template(name: "Grainy Broadcast", category: "New Modules") {
                build(branchA: [Step("camera"), Step("grain"), Step("scanlines")],
                      mods: [ModWire(input: "noise", targetIndex: 1)],
                      macros: [MacroSpec("Broadcast", routes: [
                          (1, "p1", 1, 6),      // Grain Size [0.5...8]
                          (2, "p1", 0, 0.7)])])  // Scanlines Intensity [0...1]
            },
            Template(name: "Glass Aberration", category: "New Modules") {
                build(branchA: [Step("voronoi"), Step("chromaticAberration")],
                      mods: [ModWire(input: "treble", targetIndex: 1)],
                      macros: [MacroSpec("Glass", routes: [
                          (0, "p2", 1, 6),        // Voronoi Edge Sharpness [0.5...8]
                          (1, "p1", 0.3, 2.5)])]) // Chromatic Aberration Falloff [0.1...3]
            },
            Template(name: "Kaleido Mixer", category: "New Modules") {
                build(branchA: [Step("flowField")], branchB: [Step("lineArt")], combinerType: "kaleidoMix",
                      post: [Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 2), ModWire(input: "bass", targetIndex: 0)],
                      macros: [MacroSpec("Mixer", routes: [
                          (2, "p0", 3, 14),       // Kaleido Mix Segments [2...16]
                          (3, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Wipe Transition", category: "New Modules") {
                build(branchA: [Step("plasma")], branchB: [Step("starfield")], combinerType: "wipe",
                      mods: [ModWire(input: "lfo", targetIndex: 2)],
                      macros: [MacroSpec("Wipe", routes: [(2, "p1", 0, 6.28)])]) // Wipe Angle [0...6.28]
            },
            Template(name: "Shape Pulse", category: "New Modules") {
                build(branchA: [Step("shapes"), Step("bloom")],
                      mods: [ModWire(input: "bass", targetIndex: 0)],
                      macros: [MacroSpec("Pulse", routes: [
                          (0, "p2", 0.01, 0.25),  // Shapes Softness [0.001...0.3]
                          (1, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Shape Mask Combo", category: "New Modules") {
                build(branchA: [Step("shapes", ["p1": 3])], branchB: [Step("plasma")], combinerType: "mask",
                      post: [Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "energy", targetIndex: 1)],
                      macros: [MacroSpec("Combo", routes: [
                          (2, "p0", 0.2, 0.8),    // Mask Threshold [0...1]
                          (3, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Stepped Kaleidoscope", category: "New Modules") {
                build(branchA: [Step("kaleido")],
                      mods: [ModWire(input: "sequencer", targetIndex: 0)],
                      macros: [MacroSpec("Zoom", routes: [(0, "p2", 0.3, 2.5)])]) // Kaleido Zoom [0.2...4]
            },
            Template(name: "Sequenced Grid", category: "New Modules") {
                build(branchA: [Step("gridPulse"), Step("posterize")],
                      mods: [ModWire(input: "sequencer", targetIndex: 0), ModWire(input: "clock", targetIndex: 1)],
                      macros: [MacroSpec("Steps", routes: [
                          (0, "p2", 4, 30),   // Grid Size [2...40]
                          (1, "p0", 2, 12)])]) // Posterize Levels [2...16]
            },
            Template(name: "Analog Dream", category: "New Modules") {
                build(branchA: [Step("camera"), Step("chromaticAberration"), Step("trails"), Step("grain"), Step("vignette")],
                      mods: [ModWire(input: "envelope", targetIndex: 2), ModWire(input: "noise", targetIndex: 3)],
                      macros: [MacroSpec("Feel", routes: [
                          (1, "p1", 0.3, 2.5),    // Chromatic Aberration Falloff [0.1...3]
                          (2, "p1", 0.4, 1.0),    // Trails Amount [0...1]
                          (3, "p0", 0.1, 0.6)])]) // Grain Amount [0...1]
            },
        ]
    }()

    // MARK: - Graph builder

    /// One generator or modifier subtype plus optional non-default parameter
    /// overrides, positioned automatically by `build`.
    private struct Step {
        let subtype: String
        let overrides: [String: Float]
        /// An inline LFO to pre-attach to one of this node's parameters —
        /// same mechanism a long-press on its knob gives the user, just
        /// baked into the template.
        let inlineLFO: (paramID: String, rate: Float, depth: Float, shape: Int)?
        init(_ subtype: String, _ overrides: [String: Float] = [:], inlineLFO: (paramID: String, rate: Float, depth: Float, shape: Int)? = nil) {
            self.subtype = subtype
            self.overrides = overrides
            self.inlineLFO = inlineLFO
        }
    }

    /// One Macro to pre-populate on a template, fanned out to any number of
    /// (targetIndex, paramID, rangeMin, rangeMax) routes — same
    /// `MacroAssignment` data the Macro panel/Matrix edit live.
    private struct MacroSpec {
        let name: String
        let value: Float
        let routes: [(targetIndex: Int, paramID: String, rangeMin: Float, rangeMax: Float)]
        init(_ name: String, value: Float = 0.5, routes: [(targetIndex: Int, paramID: String, rangeMin: Float, rangeMax: Float)]) {
            self.name = name
            self.value = value
            self.routes = routes
        }
    }

    /// A value-cable from a fresh Input node to a node's "mod" port.
    /// `targetIndex` indexes into the fully assembled node list, in this
    /// order: branchA nodes, then branchB nodes (if any), then the
    /// combiner (if any), then `post` nodes.
    private struct ModWire {
        let input: String
        let targetIndex: Int
    }

    /// General template assembler: one or two linear generator->modifier
    /// branches, optionally merged by a combiner, optionally followed by a
    /// further modifier chain, with any number of Input nodes patched into
    /// specific nodes' "mod" ports. Covers everything from a single bare
    /// generator up to the multi-branch Flagship patches.
    private static func build(
        branchA: [Step],
        branchB: [Step]? = nil,
        combinerType: String? = nil,
        combinerOverrides: [String: Float] = [:],
        post: [Step] = [],
        mods: [ModWire] = [],
        macros: [MacroSpec] = []
    ) -> Graph {
        var graph = Graph.empty
        let colStep: CGFloat = 300
        var mainNodes: [GraphNode] = []

        func makeStep(_ step: Step, kind: NodeKind, x: CGFloat, y: CGFloat) -> GraphNode {
            var node = NodeCatalog.makeNode(kind: kind, subtype: step.subtype, position: CGPoint(x: x, y: y))
            for (key, value) in step.overrides { node.parameters[key] = value }
            if let lfo = step.inlineLFO {
                node.paramModulators[lfo.paramID] = ParamModulator(rate: lfo.rate, depth: lfo.depth, shape: lfo.shape)
            }
            return node
        }

        let branchAY: CGFloat = branchB == nil ? 220 : 140
        var x: CGFloat = 160
        for (i, step) in branchA.enumerated() {
            let kind: NodeKind = i == 0 ? .generator : .modifier
            mainNodes.append(makeStep(step, kind: kind, x: x, y: branchAY))
            x += colStep
        }
        var mergeX = x

        if let branchB {
            var bx: CGFloat = 160
            for (i, step) in branchB.enumerated() {
                let kind: NodeKind = i == 0 ? .generator : .modifier
                mainNodes.append(makeStep(step, kind: kind, x: bx, y: 460))
                bx += colStep
            }
            mergeX = max(mergeX, bx)
        }

        var postStartX = mergeX
        if let combinerType {
            let combinerNode = makeStep(Step(combinerType, combinerOverrides), kind: .combiner, x: mergeX, y: (branchAY + 460) / 2)
            mainNodes.append(combinerNode)
            postStartX = mergeX + colStep
        }

        for (i, step) in post.enumerated() {
            mainNodes.append(makeStep(step, kind: .modifier, x: postStartX + CGFloat(i) * colStep, y: branchAY))
        }

        let outputX = postStartX + CGFloat(post.count) * colStep
        let output = NodeCatalog.makeNode(kind: .output, subtype: "output", position: CGPoint(x: outputX, y: branchAY))

        graph.nodes = mainNodes + [output]

        var connections: [GraphConnection] = []
        let branchACount = branchA.count
        let branchBCount = branchB?.count ?? 0
        let hasCombiner = combinerType != nil

        for i in 0..<(branchACount - 1) {
            connections.append(chainWire(mainNodes[i], mainNodes[i + 1]))
        }
        if branchB != nil {
            for i in 0..<(branchBCount - 1) {
                connections.append(chainWire(mainNodes[branchACount + i], mainNodes[branchACount + i + 1]))
            }
        }

        var mergePointIndex = branchACount - 1
        if hasCombiner {
            let combinerIndex = branchACount + branchBCount
            connections.append(GraphConnection(sourceNodeID: mainNodes[branchACount - 1].id, sourcePortID: "out",
                                                destNodeID: mainNodes[combinerIndex].id, destPortID: "inA", signalType: .texture))
            connections.append(GraphConnection(sourceNodeID: mainNodes[branchACount + branchBCount - 1].id, sourcePortID: "out",
                                                destNodeID: mainNodes[combinerIndex].id, destPortID: "inB", signalType: .texture))
            mergePointIndex = combinerIndex
        }

        let postStartIndex = branchACount + branchBCount + (hasCombiner ? 1 : 0)
        var previousIndex = mergePointIndex
        for i in 0..<post.count {
            connections.append(chainWire(mainNodes[previousIndex], mainNodes[postStartIndex + i]))
            previousIndex = postStartIndex + i
        }
        connections.append(GraphConnection(sourceNodeID: mainNodes[previousIndex].id, sourcePortID: "out",
                                            destNodeID: output.id, destPortID: "in", signalType: .texture))

        var inputY: CGFloat = branchAY + 620
        for wire in mods {
            let inputNode = NodeCatalog.makeNode(kind: .input, subtype: wire.input, position: CGPoint(x: 160, y: inputY))
            graph.nodes.append(inputNode)
            connections.append(GraphConnection(sourceNodeID: inputNode.id, sourcePortID: "out",
                                                destNodeID: mainNodes[wire.targetIndex].id, destPortID: "mod", signalType: .value))
            inputY += 150
        }

        graph.connections = connections

        for spec in macros {
            let macro = Macro(name: spec.name, value: spec.value)
            graph.macros.append(macro)
            for route in spec.routes {
                graph.macroAssignments.append(MacroAssignment(macroID: macro.id, nodeID: mainNodes[route.targetIndex].id, paramID: route.paramID, rangeMin: route.rangeMin, rangeMax: route.rangeMax))
            }
        }

        return graph
    }

    private static func chainWire(_ from: GraphNode, _ to: GraphNode) -> GraphConnection {
        GraphConnection(sourceNodeID: from.id, sourcePortID: "out", destNodeID: to.id, destPortID: "in", signalType: .texture)
    }
}
