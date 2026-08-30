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
    static let all: [Template] = basics + camera + faceTracking + generative + audioReactive + combined + midi + flagship + performance

    static let categories: [String] =
        ["Basics", "Camera", "Face Tracking", "Generative", "Audio Reactive", "Combiners", "MIDI", "Flagship", "Performance"]

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
                          (0, "p1", 20, 320),     // Starfield Density [20...400]
                          (0, "p2", 0, 1.5)]),    // Starfield Streak [0...2]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),  // Starfield Palette [0...5]
                               MacroSpec("Threshold", routes: [(1, "p0", 0.2, 0.9)]), // Bloom Threshold [0...1]
                               MacroSpec("Intensity", routes: [(1, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Mid Voronoi Cells", category: "Audio Reactive") {
                build(branchA: [Step("voronoi"), Step("blur")], mods: [ModWire(input: "mid", targetIndex: 0)],
                      macros: [MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.2)]),      // Voronoi Speed [0...3]
                               MacroSpec("Cells", routes: [(0, "p2", 1, 6)]),          // Voronoi Edge Sharpness [0.5...8]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Voronoi Palette [0...5]
                               MacroSpec("Blur", routes: [(1, "p0", 0, 0.7)]),         // Blur Amount [0...1]
                               MacroSpec("Quality", routes: [(1, "p1", 1, 3)])])       // Blur Quality [1...3]
            },
            Template(name: "Energy Kaleidoscope", category: "Audio Reactive") {
                build(branchA: [Step("kaleido"), Step("hueRotate"), Step("bloom")],
                      mods: [ModWire(input: "energy", targetIndex: 0), ModWire(input: "beatStrength", targetIndex: 1)],
                      macros: [MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.5)]),      // Kaleido Speed [0...3]
                               MacroSpec("Vibe", routes: [(0, "p2", 0.3, 2.5)]),       // Kaleido Zoom [0.2...4]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Kaleido Palette [0...5]
                               MacroSpec("Rotation", routes: [(1, "p0", 0, 1)]),       // Hue Rotate Rotation [0...1]
                               MacroSpec("Threshold", routes: [(2, "p0", 0.2, 0.9)]),  // Bloom Threshold [0...1]
                               MacroSpec("Intensity", routes: [(2, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Glitch Pulse", category: "Audio Reactive") {
                build(branchA: [Step("voronoi"), Step("rgbSplit"), Step("scanlines")],
                      mods: [ModWire(input: "beatStrength", targetIndex: 1)],
                      macros: [MacroSpec("Cells", routes: [(0, "p0", 4, 24)]),         // Voronoi Cell Count [2...30]
                               MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.5)]),      // Voronoi Speed [0...3]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Voronoi Palette [0...5]
                               MacroSpec("Angle", routes: [(1, "p1", 0, 6.28)]),       // RGB Split Angle [0...6.28]
                               MacroSpec("Scan Density", routes: [(2, "p0", 60, 700)]), // Scanlines Density [40...800]
                               MacroSpec("Glitch", routes: [(2, "p1", 0, 0.8)])])      // Scanlines Intensity [0...1]
            },
            Template(name: "Grid Pulse Machine", category: "Audio Reactive") {
                build(branchA: [Step("gridPulse"), Step("pixelate")], mods: [ModWire(input: "beatStrength", targetIndex: 0)],
                      macros: [MacroSpec("Speed", routes: [(0, "p1", 0.2, 3.2)]),   // Grid Pulse Speed [0...4]
                               MacroSpec("Grid Size", routes: [(0, "p2", 4, 30)]),  // Grid Size [2...40]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),     // Grid Pulse Palette [0...5]
                               MacroSpec("Chunk", routes: [(1, "p0", 2, 40)])])     // Pixelate Cell Size [1...64]
            },
            Template(name: "Gradient Wash", category: "Audio Reactive") {
                build(branchA: [Step("gradientFlow"), Step("blur"), Step("hueRotate")],
                      mods: [ModWire(input: "energy", targetIndex: 0)],
                      macros: [MacroSpec("Turbulence", routes: [(0, "p1", 0.3, 3.2)]), // Gradient Flow Turbulence [0...4]
                               MacroSpec("Wash", routes: [(0, "p2", 1, 4)]),           // Gradient Flow Scale [0.5...6]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Gradient Flow Palette [0...5]
                               MacroSpec("Blur", routes: [(1, "p0", 0, 0.7)]),         // Blur Amount [0...1]
                               MacroSpec("Rotation", routes: [(2, "p0", 0, 1)]),       // Hue Rotation [0...1]
                               MacroSpec("Saturation", routes: [(2, "p1", 0.3, 1.8)])]) // Hue Saturation [0...2]
            },
            Template(name: "Feedback Trails", category: "Audio Reactive") {
                build(branchA: [Step("plasma"), Step("feedback")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "bass", targetIndex: 1)],
                      macros: [MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.2)]),        // Plasma Speed [0...3]
                               MacroSpec("Echo", routes: [(0, "p2", 1, 4)]),             // Plasma Scale [0.5...6]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),          // Plasma Palette [0...5]
                               MacroSpec("Zoom", routes: [(1, "p1", 0.95, 1.05)])])      // Feedback Zoom [0.9...1.1]
            },
            Template(name: "Neon Tunnel", category: "Audio Reactive") {
                build(branchA: [Step("tunnel"), Step("mirror"), Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0)],
                      macros: [MacroSpec("Neon", routes: [(0, "p1", 0, 4)]),          // Tunnel Twist [0...6]
                               MacroSpec("Rings", routes: [(0, "p2", 4, 30)]),        // Tunnel Rings [2...40]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),       // Tunnel Palette [0...5]
                               MacroSpec("Offset", routes: [(1, "p1", -0.8, 0.8)]),   // Mirror Offset [-1...1]
                               MacroSpec("Intensity", routes: [(2, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
        ]
    }()

    // MARK: - MIDI (CC / Note driven)

    private static let midi: [Template] = {
        [
            Template(name: "MIDI CC Tunnel", category: "MIDI") {
                build(branchA: [Step("tunnel"), Step("scanlines")], mods: [ModWire(input: "midiCC", targetIndex: 0)],
                      macros: [MacroSpec("Twist", routes: [(0, "p1", 0, 4)]),          // Tunnel Twist [0...6]
                               MacroSpec("Depth", routes: [(0, "p2", 4, 30)]),         // Tunnel Rings [2...40]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Tunnel Palette [0...5]
                               MacroSpec("Scan Density", routes: [(1, "p0", 60, 700)]), // Scanlines Density [40...800]
                               MacroSpec("Scan", routes: [(1, "p1", 0, 0.7)])])        // Scanlines Intensity [0...1]
            },
            Template(name: "MIDI Note Rings", category: "MIDI") {
                build(branchA: [Step("rings"), Step("hueRotate")], mods: [ModWire(input: "midiNote", targetIndex: 0)],
                      macros: [MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.2)]),      // Rings Speed [0...3]
                               MacroSpec("Glow", routes: [(0, "p2", 0.05, 0.35)]),     // Rings Thickness [0.02...0.5]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Rings Palette [0...5]
                               MacroSpec("Rotation", routes: [(1, "p0", 0, 1)]),       // Hue Rotation [0...1]
                               MacroSpec("Saturation", routes: [(1, "p1", 0.5, 2)])])  // Hue Rotate Saturation [0...2]
            },
            Template(name: "MIDI Kaleido Rig", category: "MIDI") {
                build(branchA: [Step("kaleido"), Step("rgbSplit"), Step("bloom")],
                      mods: [ModWire(input: "midiCC", targetIndex: 0), ModWire(input: "midiNote", targetIndex: 1)],
                      macros: [MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.5)]),      // Kaleido Speed [0...3]
                               MacroSpec("Rig", routes: [(0, "p2", 0.3, 2.5)]),        // Kaleido Zoom [0.2...4]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Kaleido Palette [0...5]
                               MacroSpec("Angle", routes: [(1, "p1", 0, 6.28)]),       // RGB Split Angle [0...6.28]
                               MacroSpec("Threshold", routes: [(2, "p0", 0.2, 0.9)]),  // Bloom Threshold [0...1]
                               MacroSpec("Intensity", routes: [(2, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
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
                      macros: [MacroSpec("Twist", routes: [(0, "p1", 0, 4)]),          // Tunnel Twist [0...6]
                               MacroSpec("Rings", routes: [(0, "p2", 4, 30)]),         // Tunnel Rings [2...40]
                               MacroSpec("Speed", routes: [(1, "p1", 0.2, 2.2)]),      // Rings Speed [0...3]
                               MacroSpec("Thickness", routes: [(1, "p2", 0.05, 0.35)]), // Rings Thickness [0.02...0.5]
                               MacroSpec("Blend", routes: [(2, "p0", 0, 1)])])         // Blend Mix [0...1]
            },
            Template(name: "Voronoi Mask", category: "Combiners") {
                build(branchA: [Step("voronoi")], branchB: [Step("starfield")], combinerType: "mask",
                      mods: [ModWire(input: "mid", targetIndex: 0)],
                      macros: [MacroSpec("Cells", routes: [(0, "p2", 1, 6)]),          // Voronoi Edge Sharpness [0.5...8]
                               MacroSpec("Palette A", routes: [(0, "p3", 0, 5)]),      // Voronoi Palette [0...5]
                               MacroSpec("Star Speed", routes: [(1, "p0", 0.5, 6)]),   // Starfield Speed [0...8]
                               MacroSpec("Streak", routes: [(1, "p2", 0, 1.5)]),       // Starfield Streak [0...2]
                               MacroSpec("Palette B", routes: [(1, "p3", 0, 5)]),      // Starfield Palette [0...5]
                               MacroSpec("Reveal", routes: [(2, "p0", 0.2, 0.8)])])    // Mask Threshold [0...1]
            },
            Template(name: "Difference Storm", category: "Combiners") {
                build(branchA: [Step("plasma")], branchB: [Step("kaleido")], combinerType: "difference",
                      post: [Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "energy", targetIndex: 1)],
                      macros: [MacroSpec("Plasma Speed", routes: [(0, "p1", 0.2, 2.2)]), // Plasma Speed [0...3]
                               MacroSpec("Plasma Scale", routes: [(0, "p2", 1, 4)]),     // Plasma Scale [0.5...6]
                               MacroSpec("Kaleido Zoom", routes: [(1, "p2", 0.3, 2.5)]), // Kaleido Zoom [0.2...4]
                               MacroSpec("Storm", routes: [(2, "p0", 0.3, 1)]),          // Difference Amount [0...1]
                               MacroSpec("Intensity", routes: [(3, "p1", 0.3, 2.5)])])   // Bloom Intensity [0...3]
            },
            Template(name: "Layered Pulse", category: "Combiners") {
                build(branchA: [Step("gridPulse")], branchB: [Step("rings")], combinerType: "blend",
                      combinerOverrides: ["p1": 1], post: [Step("bloom")],
                      mods: [ModWire(input: "beatStrength", targetIndex: 0), ModWire(input: "bass", targetIndex: 1)],
                      macros: [MacroSpec("Grid Speed", routes: [(0, "p1", 0.2, 3.2)]),  // Grid Pulse Speed [0...4]
                               MacroSpec("Grid Size", routes: [(0, "p2", 4, 30)]),      // Grid Size [2...40]
                               MacroSpec("Rings Speed", routes: [(1, "p1", 0.2, 2.2)]), // Rings Speed [0...3]
                               MacroSpec("Layers", routes: [(2, "p0", 0, 1)]),          // Blend Mix [0...1]
                               MacroSpec("Intensity", routes: [(3, "p1", 0.3, 2.5)])])  // Bloom Intensity [0...3]
            },
            Template(name: "Displace Flow", category: "Combiners") {
                build(branchA: [Step("gradientFlow")], branchB: [Step("plasma")], combinerType: "displace",
                      post: [Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "sampleHold", targetIndex: 1)],
                      macros: [MacroSpec("Turbulence", routes: [(0, "p1", 0.3, 3.2)]), // Gradient Flow Turbulence [0...4]
                               MacroSpec("Scale A", routes: [(0, "p2", 1, 4)]),        // Gradient Flow Scale [0.5...6]
                               MacroSpec("Scale B", routes: [(1, "p2", 1, 4)]),        // Plasma Scale [0.5...6]
                               MacroSpec("Flow", routes: [(2, "p0", 0.2, 0.9)]),       // Displace Amount [0...1]
                               MacroSpec("Displace Scale", routes: [(2, "p1", 0.7, 2)]), // Displace Scale [0.5...3]
                               MacroSpec("Intensity", routes: [(3, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Luma Composite", category: "Combiners") {
                build(branchA: [Step("camera")], branchB: [Step("kaleido")], combinerType: "lumaKey",
                      mods: [ModWire(input: "envelope", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),   // Camera Exposure [0.2...2]
                               MacroSpec("Saturation", routes: [(0, "p1", 0.3, 1.8)]), // Camera Saturation [0...2]
                               MacroSpec("Kaleido Zoom", routes: [(1, "p2", 0.3, 2.5)]), // Kaleido Zoom [0.2...4]
                               MacroSpec("Composite", routes: [(2, "p0", 0.2, 0.8)]),  // Luma Key Threshold [0...1]
                               MacroSpec("Softness", routes: [(2, "p1", 0.05, 0.7)])]) // Luma Key Softness [0...1]
            },
            Template(name: "Beat Crossfade Mix", category: "Combiners") {
                build(branchA: [Step("tunnel")], branchB: [Step("rings")], combinerType: "beatCrossfade",
                      post: [Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "bass", targetIndex: 1)],
                      macros: [MacroSpec("Tunnel Twist", routes: [(0, "p1", 0, 4)]),   // Tunnel Twist [0...6]
                               MacroSpec("Rings Speed", routes: [(1, "p1", 0.2, 2.2)]), // Rings Speed [0...3]
                               MacroSpec("Thickness", routes: [(1, "p2", 0.05, 0.35)]), // Rings Thickness [0.02...0.5]
                               MacroSpec("Crossfade", routes: [(2, "p1", 0.1, 0.6)]),  // Beat Crossfade Softness [0...1]
                               MacroSpec("Intensity", routes: [(3, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Kaleido Mixer", category: "Combiners") {
                build(branchA: [Step("flowField")], branchB: [Step("lineArt")], combinerType: "kaleidoMix",
                      post: [Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 2), ModWire(input: "bass", targetIndex: 0)],
                      macros: [MacroSpec("Flow Speed", routes: [(0, "p1", 0.2, 2.2)]), // Flow Field Speed [0...3]
                               MacroSpec("Turbulence", routes: [(0, "p2", 0.3, 2.5)]), // Flow Field Turbulence [0...3]
                               MacroSpec("Line Density", routes: [(1, "p0", 4, 30)]),  // Line Art Density [2...40]
                               MacroSpec("Wobble", routes: [(1, "p2", 0.2, 1.5)]),     // Line Art Wobble [0...2]
                               MacroSpec("Mixer", routes: [(2, "p0", 3, 14)]),         // Kaleido Mix Segments [2...16]
                               MacroSpec("Mix", routes: [(2, "p1", 0.2, 0.8)]),        // Kaleido Mix Amount [0...1]
                               MacroSpec("Intensity", routes: [(3, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Wipe Transition", category: "Combiners") {
                build(branchA: [Step("plasma")], branchB: [Step("starfield")], combinerType: "wipe",
                      mods: [ModWire(input: "lfo", targetIndex: 2)],
                      macros: [MacroSpec("Complexity", routes: [(0, "p0", 2, 7)]),     // Plasma Complexity [1...8]
                               MacroSpec("Plasma Palette", routes: [(0, "p3", 0, 5)]), // Plasma Palette [0...5]
                               MacroSpec("Star Speed", routes: [(1, "p0", 0.5, 6)]),   // Starfield Speed [0...8]
                               MacroSpec("Star Palette", routes: [(1, "p3", 0, 5)]),   // Starfield Palette [0...5]
                               MacroSpec("Wipe", routes: [(2, "p0", 0, 1)]),           // Wipe Position [0...1]
                               MacroSpec("Angle", routes: [(2, "p1", 0, 6.28)]),       // Wipe Angle [0...6.28]
                               MacroSpec("Softness", routes: [(2, "p2", 0.02, 0.25)])]) // Wipe Softness [0.001...0.3]
            },
            Template(name: "Shape Mask Combo", category: "Combiners") {
                build(branchA: [Step("shapes", ["p1": 3])], branchB: [Step("plasma")], combinerType: "mask",
                      post: [Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "energy", targetIndex: 1)],
                      macros: [MacroSpec("Shape Softness", routes: [(0, "p2", 0.01, 0.25)]), // Shapes Softness [0.001...0.3]
                               MacroSpec("Shape Palette", routes: [(0, "p3", 0, 5)]),  // Shapes Palette [0...5]
                               MacroSpec("Plasma Speed", routes: [(1, "p1", 0.2, 2.2)]), // Plasma Speed [0...3]
                               MacroSpec("Plasma Scale", routes: [(1, "p2", 1, 4)]),   // Plasma Scale [0.5...6]
                               MacroSpec("Combo", routes: [(2, "p0", 0.2, 0.8)]),      // Mask Threshold [0...1]
                               MacroSpec("Intensity", routes: [(3, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
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
                      macros: [MacroSpec("Twist", routes: [(0, "p1", 0, 4)]),          // Tunnel Twist [0...6]
                               MacroSpec("Rings", routes: [(0, "p2", 4, 30)]),         // Tunnel Rings [2...40]
                               MacroSpec("Axis", routes: [(1, "p0", 0, 2)]),           // Mirror Axis [0...2]
                               MacroSpec("Offset", routes: [(1, "p1", -0.8, 0.8)]),    // Mirror Offset [-1...1]
                               MacroSpec("Angle", routes: [(2, "p1", 0, 6.28)]),       // RGB Split Angle [0...6.28]
                               MacroSpec("Scan Density", routes: [(3, "p0", 60, 700)]), // Scanlines Density [40...800]
                               MacroSpec("Scan", routes: [(3, "p1", 0, 0.7)]),         // Scanlines Intensity [0...1]
                               MacroSpec("Drive", routes: [(4, "p1", 0.3, 2.5)])])     // Bloom Intensity [0...3]
            },
            Template(name: "Cosmic Cascade", category: "Flagship") {
                build(branchA: [Step("starfield")], branchB: [Step("kaleido")], combinerType: "blend",
                      combinerOverrides: ["p1": 3],
                      post: [Step("hueRotate"), Step("bloom"), Step("feedback")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "energy", targetIndex: 1),
                             ModWire(input: "beatStrength", targetIndex: 4)],
                      macros: [MacroSpec("Density", routes: [(0, "p1", 20, 320)]),     // Starfield Density [20...400]
                               MacroSpec("Streak", routes: [(0, "p2", 0, 1.5)]),       // Starfield Streak [0...2]
                               MacroSpec("Kaleido Zoom", routes: [(1, "p2", 0.3, 2.5)]), // Kaleido Zoom [0.2...4]
                               MacroSpec("Cosmic", routes: [(2, "p0", 0, 1)]),         // Blend Mix [0...1]
                               MacroSpec("Rotation", routes: [(3, "p0", 0, 1)]),       // Hue Rotation [0...1]
                               MacroSpec("Intensity", routes: [(4, "p1", 0.3, 2.5)]),  // Bloom Intensity [0...3]
                               MacroSpec("Decay", routes: [(5, "p0", 0.5, 0.95)]),     // Feedback Decay [0...0.98]
                               MacroSpec("Feedback Zoom", routes: [(5, "p1", 0.95, 1.05)])]) // Feedback Zoom [0.9...1.1]
            },
            Template(name: "MIDI Reactive Rig", category: "Flagship") {
                build(branchA: [Step("rings")], branchB: [Step("voronoi")], combinerType: "mask",
                      post: [Step("scanlines"), Step("bloom")],
                      mods: [ModWire(input: "midiCC", targetIndex: 0), ModWire(input: "midiNote", targetIndex: 1)],
                      macros: [MacroSpec("Rings Speed", routes: [(0, "p1", 0.2, 2.2)]), // Rings Speed [0...3]
                               MacroSpec("Thickness", routes: [(0, "p2", 0.05, 0.35)]), // Rings Thickness [0.02...0.5]
                               MacroSpec("Voronoi Speed", routes: [(1, "p1", 0.2, 2.5)]), // Voronoi Speed [0...3]
                               MacroSpec("Edge", routes: [(1, "p2", 1, 6)]),           // Voronoi Edge Sharpness [0.5...8]
                               MacroSpec("Reactive", routes: [(2, "p0", 0.2, 0.8)]),   // Mask Threshold [0...1]
                               MacroSpec("Scan", routes: [(3, "p1", 0, 0.7)]),         // Scanlines Intensity [0...1]
                               MacroSpec("Intensity", routes: [(4, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Signal Storm", category: "Flagship") {
                build(branchA: [Step("plasma"), Step("hueRotate")], branchB: [Step("gridPulse"), Step("pixelate")],
                      combinerType: "difference", post: [Step("rgbSplit"), Step("bloom")],
                      mods: [ModWire(input: "mid", targetIndex: 0), ModWire(input: "beatStrength", targetIndex: 2),
                             ModWire(input: "treble", targetIndex: 5)],
                      macros: [MacroSpec("Plasma Speed", routes: [(0, "p1", 0.2, 2.2)]), // Plasma Speed [0...3]
                               MacroSpec("Plasma Scale", routes: [(0, "p2", 1, 4)]),     // Plasma Scale [0.5...6]
                               MacroSpec("Hue Rotation", routes: [(1, "p0", 0, 1)]),     // Hue Rotation [0...1]
                               MacroSpec("Grid Speed", routes: [(2, "p1", 0.2, 3.2)]),   // Grid Pulse Speed [0...4]
                               MacroSpec("Pixel Size", routes: [(3, "p0", 2, 40)]),      // Pixelate Cell Size [1...64]
                               MacroSpec("Storm", routes: [(4, "p0", 0.3, 1)]),          // Difference Amount [0...1]
                               MacroSpec("Intensity", routes: [(6, "p1", 0.3, 2.5)])])   // Bloom Intensity [0...3]
            },
            Template(name: "Deep Feedback Wash", category: "Flagship") {
                build(branchA: [Step("gradientFlow"), Step("blur"), Step("feedback"), Step("hueRotate")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "energy", targetIndex: 1),
                             ModWire(input: "bass", targetIndex: 2)],
                      macros: [MacroSpec("Turbulence", routes: [(0, "p1", 0.3, 3.2)]), // Gradient Flow Turbulence [0...4]
                               MacroSpec("Depth", routes: [(0, "p2", 1, 4)]),          // Gradient Flow Scale [0.5...6]
                               MacroSpec("Quality", routes: [(1, "p1", 1, 3)]),        // Blur Quality [1...3]
                               MacroSpec("Decay", routes: [(2, "p0", 0.5, 0.95)]),     // Feedback Decay [0...0.98]
                               MacroSpec("Feedback Zoom", routes: [(2, "p1", 0.95, 1.05)]), // Feedback Zoom [0.9...1.1]
                               MacroSpec("Rotation", routes: [(3, "p0", 0, 1)])])      // Hue Rotation [0...1]
            },
            Template(name: "Grand Finale", category: "Flagship") {
                build(branchA: [Step("camera"), Step("chromaKey"),
                                Step("twirl", inlineLFO: (paramID: "p0", rate: 0.15, depth: 0.5, shape: 0))],
                      branchB: [Step("fractal", ["p2": 0]), Step("posterize")],
                      combinerType: "displace",
                      post: [Step("bloom"), Step("vignette"),
                             Step("feedback", inlineLFO: (paramID: "p0", rate: 0.1, depth: 0.3, shape: 0))],
                      mods: [ModWire(input: "noise", targetIndex: 3)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),   // Camera Exposure [0.2...2]
                               MacroSpec("Key", routes: [(1, "p0", 0.15, 0.6)]),       // Chroma Key Threshold [0...1]
                               MacroSpec("Twirl", routes: [(2, "p0", -2, 2)]),         // Twirl Strength [-3...3]
                               MacroSpec("Detail", routes: [(3, "p1", 0.5, 2.2)]),     // Fractal Detail [0.3...3]
                               MacroSpec("Posterize", routes: [(4, "p0", 3, 12)]),     // Posterize Levels [2...16]
                               MacroSpec("Displace", routes: [(5, "p1", 0.7, 2)]),     // Displace Scale [0.5...3]
                               MacroSpec("Bloom", routes: [(6, "p1", 0.2, 2.5)]),      // Bloom Intensity [0...3]
                               MacroSpec("Vignette", routes: [(7, "p0", 0.2, 0.8)])])  // Vignette Amount [0...1]
            },
            Template(name: "Orbital Drift", category: "Flagship") {
                build(branchA: [Step("particles")], branchB: [Step("reaction")], combinerType: "lumaKey",
                      post: [Step("hueRotate"), Step("bloom")],
                      mods: [ModWire(input: "beatStrength", targetIndex: 0), ModWire(input: "bass", targetIndex: 1)],
                      macros: [MacroSpec("Drift", routes: [(0, "p0", 10, 140)]),       // Particles Count [4...160]
                               MacroSpec("Particle Speed", routes: [(0, "p1", 0.3, 3.2)]), // Particles Speed [0...4]
                               MacroSpec("Size", routes: [(0, "p2", 0.2, 1.6)]),       // Particles Size [0.1...2]
                               MacroSpec("Growth", routes: [(1, "p0", 0.2, 1.8)]),     // Reaction Growth [0...2]
                               MacroSpec("Seed Rate", routes: [(1, "p2", 0.1, 0.8)]),  // Reaction Seed Rate [0...1]
                               MacroSpec("Luma", routes: [(2, "p0", 0.2, 0.8)]),       // Luma Key Threshold [0...1]
                               MacroSpec("Rotation", routes: [(3, "p0", 0, 1)]),       // Hue Rotation [0...1]
                               MacroSpec("Intensity", routes: [(4, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
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
                      macros: [MacroSpec("Morph", routes: [(0, "p0", 2, 7)]),          // Plasma Complexity [1...8]
                               MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.2)]),      // Plasma Speed [0...3]
                               MacroSpec("Scale", routes: [(0, "p2", 1, 4)]),          // Plasma Scale [0.5...6]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Plasma Palette [0...5]
                               MacroSpec("Rotation", routes: [(1, "p0", 0, 1)]),       // Hue Rotate Rotation [0...1]
                               MacroSpec("Saturation", routes: [(1, "p1", 0.3, 1.8)]), // Hue Rotate Saturation [0...2]
                               MacroSpec("Threshold", routes: [(2, "p0", 0.2, 0.9)]),  // Bloom Threshold [0...1]
                               MacroSpec("Intensity", routes: [(2, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Twin Macro Rig", category: "Performance") {
                build(branchA: [Step("voronoi")], branchB: [Step("starfield")], combinerType: "blend",
                      post: [Step("bloom")],
                      macros: [MacroSpec("Mix", routes: [(2, "p0", 0, 1)]),            // Blend Mix [0...1]
                               MacroSpec("Chaos", routes: [
                                   (0, "p0", 5, 25),    // Voronoi Cell Count [2...30]
                                   (1, "p0", 0.5, 6)]),  // Starfield Speed [0...8]
                               MacroSpec("Edge", routes: [(0, "p2", 1, 6)]),           // Voronoi Edge Sharpness [0.5...8]
                               MacroSpec("Voronoi Palette", routes: [(0, "p3", 0, 5)]), // Voronoi Palette [0...5]
                               MacroSpec("Streak", routes: [(1, "p2", 0, 1.5)]),       // Starfield Streak [0...2]
                               MacroSpec("Star Palette", routes: [(1, "p3", 0, 5)]),   // Starfield Palette [0...5]
                               MacroSpec("Intensity", routes: [(3, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Triple Threat", category: "Performance") {
                build(branchA: [Step("tunnel", inlineLFO: (paramID: "p1", rate: 0.4, depth: 0.5, shape: 1)),
                                Step("mirror"),
                                Step("rgbSplit", inlineLFO: (paramID: "p1", rate: 0.2, depth: 1.0, shape: 3)),
                                Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0)],
                      macros: [MacroSpec("Rings", routes: [(0, "p2", 4, 30)]),         // Tunnel Rings [2...40]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Tunnel Palette [0...5]
                               MacroSpec("Axis", routes: [(1, "p0", 0, 2)]),           // Mirror Axis [0...2]
                               MacroSpec("Offset", routes: [(1, "p1", -0.8, 0.8)]),    // Mirror Offset [-1...1]
                               MacroSpec("Split Amount", routes: [(2, "p0", 0, 0.08)]), // RGB Split Amount [0...0.1]
                               MacroSpec("Threshold", routes: [(3, "p0", 0.2, 0.9)]),  // Bloom Threshold [0...1]
                               MacroSpec("Intensity", routes: [(3, "p1", 0.2, 2.8)])]) // Bloom Intensity [0...3]
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

    // MARK: - Camera (camera as the primary subject, one or two physical
    // sources, straight through a modifier chain or blended together)

    private static let camera: [Template] = {
        [
            Template(name: "Camera Chroma Twirl", category: "Camera") {
                build(branchA: [Step("camera"), Step("chromaKey"), Step("twirl")],
                      mods: [ModWire(input: "envelope", targetIndex: 2)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),   // Camera Exposure [0.2...2]
                               MacroSpec("Saturation", routes: [(0, "p1", 0.3, 1.8)]), // Camera Saturation [0...2]
                               MacroSpec("Key", routes: [(1, "p0", 0.1, 0.7)]),        // Chroma Key Threshold [0...1]
                               MacroSpec("Softness", routes: [(1, "p1", 0.05, 0.7)]),  // Chroma Key Softness [0...1]
                               MacroSpec("Twirl", routes: [(2, "p0", -2.5, 2.5)]),     // Twirl Strength [-3...3]
                               MacroSpec("Radius", routes: [(2, "p1", 0.3, 1.4)])])    // Twirl Radius [0.2...1.5]
            },
            Template(name: "Camera Datamosh", category: "Camera") {
                build(branchA: [Step("camera"), Step("datamosh"), Step("posterize")],
                      mods: [ModWire(input: "sampleHold", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),   // Camera Exposure [0.2...2]
                               MacroSpec("Saturation", routes: [(0, "p1", 0.3, 1.8)]), // Camera Saturation [0...2]
                               MacroSpec("Mosh", routes: [(1, "p0", 0.1, 0.8)]),       // Datamosh Amount [0...1]
                               MacroSpec("Block Size", routes: [(1, "p1", 4, 50)]),    // Datamosh Block Size [2...64]
                               MacroSpec("Posterize", routes: [(2, "p0", 2, 12)]),     // Posterize Levels [2...16]
                               MacroSpec("Gamma", routes: [(2, "p1", 0.5, 2.2)])])     // Posterize Gamma [0.3...3]
            },
            Template(name: "Grainy Broadcast", category: "Camera") {
                build(branchA: [Step("camera"), Step("grain"), Step("scanlines")],
                      mods: [ModWire(input: "noise", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),   // Camera Exposure [0.2...2]
                               MacroSpec("Saturation", routes: [(0, "p1", 0.3, 1.8)]), // Camera Saturation [0...2]
                               MacroSpec("Broadcast", routes: [(1, "p1", 1, 6)]),      // Grain Size [0.5...8]
                               MacroSpec("Scan Density", routes: [(2, "p0", 60, 700)]), // Scanlines Density [40...800]
                               MacroSpec("Scan", routes: [(2, "p1", 0, 0.7)])])        // Scanlines Intensity [0...1]
            },
            Template(name: "Analog Dream", category: "Camera") {
                build(branchA: [Step("camera"), Step("chromaticAberration"), Step("trails"), Step("grain"), Step("vignette")],
                      mods: [ModWire(input: "envelope", targetIndex: 2), ModWire(input: "noise", targetIndex: 3)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),   // Camera Exposure [0.2...2]
                               MacroSpec("Saturation", routes: [(0, "p1", 0.3, 1.8)]), // Camera Saturation [0...2]
                               MacroSpec("Aberration", routes: [(1, "p0", 0.005, 0.04)]), // Chromatic Aberration Amount [0...0.05]
                               MacroSpec("Falloff", routes: [(1, "p1", 0.3, 2.5)]),    // Chromatic Aberration Falloff [0.1...3]
                               MacroSpec("Trails Amount", routes: [(2, "p1", 0.4, 1.0)]), // Trails Amount [0...1]
                               MacroSpec("Grain Amount", routes: [(3, "p0", 0.1, 0.6)]), // Grain Amount [0...1]
                               MacroSpec("Vignette", routes: [(4, "p0", 0.2, 0.8)])])  // Vignette Amount [0...1]
            },
            Template(name: "Camera Video Wall", category: "Camera") {
                build(branchA: [Step("camera"), Step("mosaic")],
                      mods: [ModWire(input: "beatStrength", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),    // Camera Exposure [0.2...2]
                               MacroSpec("Grid", routes: [(1, "p0", 2, 12)]),           // Mosaic Grid Size [2...20]
                               MacroSpec("Gap", routes: [(1, "p1", 0, 0.2)])])          // Mosaic Gap [0...0.3]
            },
            Template(name: "Camera Puzzle Break", category: "Camera") {
                build(branchA: [Step("camera"), Step("shuffle")],
                      mods: [ModWire(input: "beatStrength", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),    // Camera Exposure [0.2...2]
                               MacroSpec("Grid", routes: [(1, "p0", 2, 8)]),            // Shuffle Grid Size [2...10]
                               MacroSpec("Seed", routes: [(1, "p1", 0, 1)]),            // Shuffle Seed [0...1]
                               MacroSpec("Scramble", routes: [(1, "p2", 0, 1)])])       // Shuffle Amount [0...1]
            },
            Template(name: "Camera Negative", category: "Camera") {
                build(branchA: [Step("camera"), Step("invert"), Step("chromaticAberration")],
                      mods: [ModWire(input: "beatStrength", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),   // Camera Exposure [0.2...2]
                               MacroSpec("Negative", routes: [(1, "p0", 0, 1)]),       // Invert Amount [0...1]
                               MacroSpec("Falloff", routes: [(2, "p1", 0.3, 2.2)])])   // Chromatic Aberration Falloff [0.1...3]
            },
            Template(name: "Strobe Pulse", category: "Camera") {
                build(branchA: [Step("camera"), Step("strobe")],
                      mods: [ModWire(input: "beatStrength", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),   // Camera Exposure [0.2...2]
                               MacroSpec("Rate", routes: [(1, "p0", 2, 14)]),          // Strobe Rate [0.5...20]
                               MacroSpec("Amount", routes: [(1, "p1", 0.2, 1)]),       // Strobe Amount [0...1]
                               MacroSpec("Duty", routes: [(1, "p2", 0.05, 0.6)]),      // Strobe Duty [0.05...0.95]
                               MacroSpec("Color", routes: [(1, "p3", 0, 1)])])         // Strobe Color (black<->white)
            },
            Template(name: "Camera VHS", category: "Camera") {
                build(branchA: [Step("camera"), Step("vhs"), Step("scanlines")],
                      mods: [ModWire(input: "noise", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),   // Camera Exposure [0.2...2]
                               MacroSpec("Tracking", routes: [(1, "p0", 0.1, 0.9)]),   // VHS Tracking [0...1]
                               MacroSpec("Static", routes: [(1, "p1", 0.1, 0.7)]),     // VHS Noise [0...1]
                               MacroSpec("Bleed", routes: [(1, "p2", 0.1, 0.8)]),      // VHS Color Bleed [0...1]
                               MacroSpec("Scan", routes: [(2, "p1", 0, 0.6)])])        // Scanlines Intensity [0...1]
            },
            Template(name: "Old Film Reel", category: "Camera") {
                build(branchA: [Step("camera"), Step("oldFilm"), Step("vignette")],
                      mods: [ModWire(input: "envelope", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),   // Camera Exposure [0.2...2]
                               MacroSpec("Flicker", routes: [(1, "p0", 0.1, 0.7)]),    // Old Film Flicker [0...1]
                               MacroSpec("Scratches", routes: [(1, "p1", 0.1, 0.7)]),  // Old Film Scratches [0...1]
                               MacroSpec("Sepia", routes: [(1, "p2", 0.2, 1)]),        // Old Film Sepia [0...1]
                               MacroSpec("Vignette", routes: [(2, "p0", 0.2, 0.8)])])  // Vignette Amount [0...1]
            },
            Template(name: "Camera Light Orb", category: "Camera") {
                build(branchA: [Step("camera"), Step("lightOrb"), Step("bloom")],
                      mods: [ModWire(input: "energy", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),      // Camera Exposure [0.2...2]
                               MacroSpec("Orb Speed", routes: [(1, "p0", 0.4, 2.4)]),     // Light Orb Speed [0...3]
                               MacroSpec("Edge Sense", routes: [(1, "p1", 0.2, 1)]),      // Light Orb Edge Sensitivity [0...1]
                               MacroSpec("Glow Size", routes: [(1, "p2", 0.02, 0.12)]),   // Light Orb Glow Size [0.01...0.2]
                               MacroSpec("Orb Palette", routes: [(1, "p3", 0, 5)]),       // Light Orb Palette [0...5]
                               MacroSpec("Intensity", routes: [(2, "p1", 0.3, 2.2)])])    // Bloom Intensity [0...3]
            },
            Template(name: "Camera Follow Spot", category: "Camera") {
                build(branchA: [Step("camera"), Step("spotlight"), Step("bloom")],
                      mods: [ModWire(input: "energy", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),      // Camera Exposure [0.2...2]
                               MacroSpec("Spot Speed", routes: [(1, "p0", 0.4, 2.4)]),    // Spotlight Speed [0...3]
                               MacroSpec("Edge Sense", routes: [(1, "p1", 0.2, 1)]),      // Spotlight Edge Sensitivity [0...1]
                               MacroSpec("Beam Size", routes: [(1, "p2", 0.03, 0.2)]),    // Spotlight Beam Size [0.01...0.3]
                               MacroSpec("Softness", routes: [(1, "p3", 0.3, 2)]),        // Spotlight Softness [0.2...3]
                               MacroSpec("Intensity", routes: [(2, "p1", 0.3, 2.2)])])    // Bloom Intensity [0...3]
            },
            // Two physical cameras in one scene — your own device's camera
            // blended with another device's NDI broadcast (a second phone
            // running the free "NDI Camera" app, say). Pick the NDI Source
            // node's "..." menu → Choose NDI Source once it's on the same
            // network — it stays black until you do.
            Template(name: "Two Cameras Blend", category: "Camera") {
                build(branchA: [Step("camera")], branchB: [Step("ndiSource")], combinerType: "blend",
                      combinerOverrides: ["p1": 3],
                      post: [Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 2)],
                      macros: [MacroSpec("Exposure A", routes: [(0, "p0", 0.4, 1.6)]),  // Camera Exposure [0.2...2]
                               MacroSpec("Exposure B", routes: [(1, "p0", 0.4, 1.6)]),  // NDI Source Exposure [0.2...2]
                               MacroSpec("Mix", routes: [(2, "p0", 0, 1)]),             // Blend Mix [0...1]
                               MacroSpec("Intensity", routes: [(3, "p1", 0.3, 2.2)])])  // Bloom Intensity [0...3]
            },
        ]
    }()

    // MARK: - Face Tracking (real-time face detection driving the shot)

    private static let faceTracking: [Template] = {
        [
            Template(name: "Face Reactive", category: "Face Tracking") {
                build(branchA: [Step("camera"), Step("vignette"), Step("bloom")],
                      mods: [ModWire(input: "faceDetected", targetIndex: 2)], // Bloom Intensity jumps when a face is in frame
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),   // Camera Exposure [0.2...2]
                               MacroSpec("Saturation", routes: [(0, "p1", 0, 1.8)]),   // Camera Saturation [0...2]
                               MacroSpec("Vignette", routes: [(1, "p0", 0.1, 0.7)])])  // Vignette Amount [0...1]
            },
            Template(name: "Face Reveal Mask", category: "Face Tracking") {
                build(branchA: [Step("shapes", ["p1": 3])], branchB: [Step("camera")], combinerType: "mask",
                      post: [Step("bloom"), Step("rotate")],
                      mods: [ModWire(input: "faceDetected", targetIndex: 2)], // Mask Threshold snaps open/closed with a face
                      macros: [MacroSpec("Shape Softness", routes: [(0, "p2", 0.01, 0.25)]), // Shapes Softness [0.001...0.3]
                               MacroSpec("Exposure", routes: [(1, "p0", 0.4, 1.6)]),   // Camera Exposure [0.2...2]
                               MacroSpec("Saturation", routes: [(1, "p1", 0, 1.8)]),   // Camera Saturation [0...2]
                               MacroSpec("Intensity", routes: [(3, "p1", 0.3, 2.2)]),  // Bloom Intensity [0...3]
                               MacroSpec("Spin", routes: [(4, "p0", -1.5, 1.5)])])     // Rotate Speed [-2...2]
            },
            Template(name: "Face Close-Up", category: "Face Tracking") {
                build(branchA: [Step("camera"), Step("faceZoom")],
                      mods: [ModWire(input: "faceDetected", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),       // Camera Exposure [0.2...2]
                               MacroSpec("Padding", routes: [(1, "p0", 1.3, 3)]),          // Face Close-Up Padding [1...4]
                               MacroSpec("Vertical Bias", routes: [(1, "p1", -0.25, 0.1)]), // Face Close-Up Vertical Bias [-0.3...0.3]
                               MacroSpec("Fallback Zoom", routes: [(1, "p2", 1, 2.2)])])   // Face Close-Up Fallback Zoom [1...3]
            },
            Template(name: "Face Spotlight", category: "Face Tracking") {
                build(branchA: [Step("camera"), Step("faceSpotlight"), Step("bloom")],
                      mods: [ModWire(input: "energy", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),        // Camera Exposure [0.2...2]
                               MacroSpec("Follow Speed", routes: [(1, "p0", 0.15, 0.7)]),   // Face Spotlight Follow Speed [0.05...1]
                               MacroSpec("Beam Size", routes: [(1, "p1", 0.05, 0.2)]),      // Face Spotlight Beam Size [0.01...0.3]
                               MacroSpec("Softness", routes: [(1, "p2", 0.3, 2)]),          // Face Spotlight Softness [0.2...3]
                               MacroSpec("Intensity", routes: [(2, "p1", 0.3, 2.2)])])      // Bloom Intensity [0...3]
            },
            Template(name: "Face Grid", category: "Face Tracking") {
                build(branchA: [Step("camera"), Step("faceGrid")],
                      mods: [ModWire(input: "faceDetected", targetIndex: 1)],
                      macros: [MacroSpec("Exposure", routes: [(0, "p0", 0.4, 1.6)]),  // Camera Exposure [0.2...2]
                               MacroSpec("Padding", routes: [(1, "p0", 1.3, 3)]),     // Face Grid Padding [1...4]
                               MacroSpec("Gap", routes: [(1, "p1", 0, 0.04)])])       // Face Grid Gap [0...0.06]
            },
        ]
    }()

    // MARK: - Generative (pure generator chains, no camera/combiner)

    private static let generative: [Template] = {
        [
            Template(name: "Fractal Zoom", category: "Generative") {
                build(branchA: [Step("fractal", ["p2": 0]), Step("bloom")],
                      mods: [ModWire(input: "envelope", targetIndex: 0)],
                      macros: [MacroSpec("Zoom", routes: [(0, "p0", 0.5, 4)]),         // Fractal Zoom [0.3...8]
                               MacroSpec("Detail", routes: [(0, "p1", 0.5, 2.2)]),     // Fractal Detail [0.3...3]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Fractal Palette [0...5]
                               MacroSpec("Threshold", routes: [(1, "p0", 0.2, 0.9)]),  // Bloom Threshold [0...1]
                               MacroSpec("Intensity", routes: [(1, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Julia Drift", category: "Generative") {
                build(branchA: [Step("fractal", ["p2": 1]), Step("hueRotate")],
                      mods: [ModWire(input: "noise", targetIndex: 0)],
                      macros: [MacroSpec("Julia", routes: [(0, "p1", 0.5, 2.5)]),      // Fractal Detail [0.3...3]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Fractal Palette [0...5]
                               MacroSpec("Rotation", routes: [(1, "p0", 0, 1)]),       // Hue Rotation [0...1]
                               MacroSpec("Saturation", routes: [(1, "p1", 0.3, 1.8)])]) // Hue Rotate Saturation [0...2]
            },
            Template(name: "Reaction Bloom", category: "Generative") {
                build(branchA: [Step("reaction"), Step("bloom")], mods: [ModWire(input: "bass", targetIndex: 0)],
                      macros: [MacroSpec("Grow", routes: [(0, "p0", 0.3, 1.8)]),       // Reaction Growth [0...2]
                               MacroSpec("Speed", routes: [(0, "p1", 0.3, 2.2)]),      // Reaction Speed [0.1...3]
                               MacroSpec("Seed Rate", routes: [(0, "p2", 0.1, 0.8)]),  // Reaction Seed Rate [0...1]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Reaction Palette [0...5]
                               MacroSpec("Threshold", routes: [(1, "p0", 0.2, 0.9)]),  // Bloom Threshold [0...1]
                               MacroSpec("Intensity", routes: [(1, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Matrix Cascade", category: "Generative") {
                build(branchA: [Step("matrixRain"), Step("scanlines")], mods: [ModWire(input: "clock", targetIndex: 0)],
                      macros: [MacroSpec("Cascade", routes: [(0, "p1", 15, 60)]),      // Matrix Rain Density [10...80]
                               MacroSpec("Glyph Size", routes: [(0, "p2", 0.03, 0.2)]), // Matrix Rain Glyph Size [0.02...0.3]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Matrix Rain Palette [0...5]
                               MacroSpec("Scan Density", routes: [(1, "p0", 60, 700)]), // Scanlines Density [40...800]
                               MacroSpec("Scan", routes: [(1, "p1", 0, 0.7)])])        // Scanlines Intensity [0...1]
            },
            Template(name: "Particle Storm", category: "Generative") {
                build(branchA: [Step("particles"), Step("bloom")], mods: [ModWire(input: "beatStrength", targetIndex: 0)],
                      macros: [MacroSpec("Speed", routes: [(0, "p1", 0.3, 3.2)]),      // Particles Speed [0...4]
                               MacroSpec("Storm", routes: [(0, "p2", 0.3, 1.8)]),      // Particles Size [0.1...2]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Particles Palette [0...5]
                               MacroSpec("Threshold", routes: [(1, "p0", 0.2, 0.9)]),  // Bloom Threshold [0...1]
                               MacroSpec("Intensity", routes: [(1, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Edge Sketch", category: "Generative") {
                build(branchA: [Step("voronoi"), Step("edgeDetect")], mods: [ModWire(input: "mid", targetIndex: 1)],
                      macros: [MacroSpec("Cells", routes: [(0, "p0", 4, 24)]),         // Voronoi Cell Count [2...30]
                               MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.5)]),      // Voronoi Speed [0...3]
                               MacroSpec("Sketch", routes: [(0, "p2", 1, 6)]),         // Voronoi Edge Sharpness [0.5...8]
                               MacroSpec("Threshold", routes: [(1, "p0", 0.1, 0.6)]),  // Edge Detect Threshold [0...1]
                               MacroSpec("Mix", routes: [(1, "p1", 0.3, 1)])])         // Edge Detect Mix [0...1]
            },
            Template(name: "Vignette Noir", category: "Generative") {
                build(branchA: [Step("starfield"), Step("vignette"), Step("posterize")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "treble", targetIndex: 1)],
                      macros: [MacroSpec("Density", routes: [(0, "p1", 20, 320)]),     // Starfield Density [20...400]
                               MacroSpec("Streak", routes: [(0, "p2", 0, 1.5)]),       // Starfield Streak [0...2]
                               MacroSpec("Noir", routes: [(1, "p0", 0.2, 0.9)]),       // Vignette Amount [0...1]
                               MacroSpec("Grain", routes: [(1, "p1", 0.05, 0.6)]),     // Vignette Grain [0...1]
                               MacroSpec("Posterize", routes: [(2, "p0", 2, 10)]),     // Posterize Levels [2...16]
                               MacroSpec("Gamma", routes: [(2, "p1", 0.5, 2.2)])])     // Posterize Gamma [0.3...3]
            },
            Template(name: "Clocked Grid", category: "Generative") {
                build(branchA: [Step("gridPulse"), Step("posterize")], mods: [ModWire(input: "clock", targetIndex: 0)],
                      macros: [MacroSpec("Speed", routes: [(0, "p1", 0.2, 3.2)]),      // Grid Pulse Speed [0...4]
                               MacroSpec("Clock", routes: [(0, "p2", 4, 30)]),         // Grid Size [2...40]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Grid Pulse Palette [0...5]
                               MacroSpec("Posterize", routes: [(1, "p0", 2, 12)]),     // Posterize Levels [2...16]
                               MacroSpec("Gamma", routes: [(1, "p1", 0.5, 2.2)])])     // Posterize Gamma [0.3...3]
            },
            Template(name: "Noise Drift Field", category: "Generative") {
                build(branchA: [Step("gradientFlow"), Step("twirl")],
                      mods: [ModWire(input: "noise", targetIndex: 0), ModWire(input: "envelope", targetIndex: 1)],
                      macros: [MacroSpec("Turbulence", routes: [(0, "p1", 0.3, 3.2)]), // Gradient Flow Turbulence [0...4]
                               MacroSpec("Drift", routes: [(0, "p2", 1, 4)]),          // Gradient Flow Scale [0.5...6]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Gradient Flow Palette [0...5]
                               MacroSpec("Twirl", routes: [(1, "p0", -2.5, 2.5)]),     // Twirl Strength [-3...3]
                               MacroSpec("Radius", routes: [(1, "p1", 0.3, 1.4)])])    // Twirl Radius [0.2...1.5]
            },
            Template(name: "Flow Field Threads", category: "Generative") {
                build(branchA: [Step("flowField"), Step("bloom")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "bass", targetIndex: 1)],
                      macros: [MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.2)]),      // Flow Field Speed [0...3]
                               MacroSpec("Threads", routes: [(0, "p2", 0.3, 2.5)]),    // Flow Field Turbulence [0...3]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Flow Field Palette [0...5]
                               MacroSpec("Threshold", routes: [(1, "p0", 0.2, 0.9)]),  // Bloom Threshold [0...1]
                               MacroSpec("Intensity", routes: [(1, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
            Template(name: "Line Art Sketch", category: "Generative") {
                build(branchA: [Step("lineArt"), Step("vignette")],
                      mods: [ModWire(input: "mid", targetIndex: 0)],
                      macros: [MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.2)]),      // Line Art Speed [0...3]
                               MacroSpec("Sketch", routes: [(0, "p2", 0.2, 1.5)]),     // Line Art Wobble [0...2]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Line Art Palette [0...5]
                               MacroSpec("Vignette", routes: [(1, "p0", 0.2, 0.8)]),   // Vignette Amount [0...1]
                               MacroSpec("Grain", routes: [(1, "p1", 0.05, 0.6)])])    // Vignette Grain [0...1]
            },
            Template(name: "Trail Blaze", category: "Generative") {
                build(branchA: [Step("plasma"), Step("trails")],
                      mods: [ModWire(input: "lfo", targetIndex: 0), ModWire(input: "beatStrength", targetIndex: 1)],
                      macros: [MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.2)]),      // Plasma Speed [0...3]
                               MacroSpec("Blaze", routes: [(0, "p2", 1, 4)]),          // Plasma Scale [0.5...6]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Plasma Palette [0...5]
                               MacroSpec("Trails Amount", routes: [(1, "p1", 0.4, 1)])]) // Trails Amount [0...1]
            },
            Template(name: "Glass Aberration", category: "Generative") {
                build(branchA: [Step("voronoi"), Step("chromaticAberration")],
                      mods: [ModWire(input: "treble", targetIndex: 1)],
                      macros: [MacroSpec("Cells", routes: [(0, "p0", 4, 24)]),         // Voronoi Cell Count [2...30]
                               MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.5)]),      // Voronoi Speed [0...3]
                               MacroSpec("Glass", routes: [(0, "p2", 1, 6)]),          // Voronoi Edge Sharpness [0.5...8]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Voronoi Palette [0...5]
                               MacroSpec("Falloff", routes: [(1, "p1", 0.3, 2.5)])])   // Chromatic Aberration Falloff [0.1...3]
            },
            Template(name: "Stepped Kaleidoscope", category: "Generative") {
                build(branchA: [Step("kaleido")],
                      mods: [ModWire(input: "sequencer", targetIndex: 0)],
                      macros: [MacroSpec("Segments", routes: [(0, "p0", 3, 20)]),      // Kaleido Segments [2...24]
                               MacroSpec("Speed", routes: [(0, "p1", 0.2, 2.5)]),      // Kaleido Speed [0...3]
                               MacroSpec("Zoom", routes: [(0, "p2", 0.3, 2.5)]),       // Kaleido Zoom [0.2...4]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)])])       // Kaleido Palette [0...5]
            },
            Template(name: "Sequenced Grid", category: "Generative") {
                build(branchA: [Step("gridPulse"), Step("posterize")],
                      mods: [ModWire(input: "sequencer", targetIndex: 0), ModWire(input: "clock", targetIndex: 1)],
                      macros: [MacroSpec("Speed", routes: [(0, "p1", 0.2, 3.2)]),      // Grid Pulse Speed [0...4]
                               MacroSpec("Steps", routes: [(0, "p2", 4, 30)]),         // Grid Size [2...40]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Grid Pulse Palette [0...5]
                               MacroSpec("Posterize", routes: [(1, "p0", 2, 12)]),     // Posterize Levels [2...16]
                               MacroSpec("Gamma", routes: [(1, "p1", 0.5, 2.2)])])     // Posterize Gamma [0.3...3]
            },
            Template(name: "Shape Pulse", category: "Generative") {
                build(branchA: [Step("shapes"), Step("bloom")],
                      mods: [ModWire(input: "bass", targetIndex: 0)],
                      macros: [MacroSpec("Shape", routes: [(0, "p1", 0, 4)]),          // Shapes type [Circle...Stripes]
                               MacroSpec("Pulse", routes: [(0, "p2", 0.01, 0.25)]),    // Shapes Softness [0.001...0.3]
                               MacroSpec("Palette", routes: [(0, "p3", 0, 5)]),        // Shapes Palette [0...5]
                               MacroSpec("Threshold", routes: [(1, "p0", 0.2, 0.9)]),  // Bloom Threshold [0...1]
                               MacroSpec("Intensity", routes: [(1, "p1", 0.3, 2.5)])]) // Bloom Intensity [0...3]
            },
        ]
    }()

    // MARK: - Graph builder

    /// One generator or modifier subtype plus optional non-default parameter
    /// overrides, positioned automatically by `build`.
    struct Step {
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
    struct MacroSpec {
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
    struct ModWire {
        let input: String
        let targetIndex: Int
    }

    /// General template assembler: one or two linear generator->modifier
    /// branches, optionally merged by a combiner, optionally followed by a
    /// further modifier chain, with any number of Input nodes patched into
    /// specific nodes' "mod" ports. Covers everything from a single bare
    /// generator up to the multi-branch Flagship patches.
    static func build(
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
