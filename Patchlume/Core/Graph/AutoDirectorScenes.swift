import CoreGraphics
import Foundation

/// Curated scene library for `AutoDirectorEngine` — deliberately NOT
/// random graph composition (way too easy to land on a broken/ugly
/// combination unattended, with nobody there to fix it) but a fixed set
/// of hand-picked, always-good-looking scenes tagged by `mood`, so the
/// director can pick contextually (lively room -> lean toward `.camera`/
/// `.hybrid`, quiet room -> lean toward `.generative`) instead of just
/// cycling blindly. Every scene bakes in its own inline LFOs and/or audio
/// `ModWire`s so it stays alive on its own, AND ships 3-4 macros
/// (`MacroSpec`, same mechanism the hand-authored templates use) —
/// `AutoDirectorEngine` continuously rides those live once a scene is
/// current, which is what actually reads as "the room is being listened
/// to" rather than just each scene's own fixed baked-in LFOs repeating on
/// their own schedule regardless of what's happening in the room.
enum AutoDirectorScenes {
    struct Scene {
        enum Mood { case camera, generative, hybrid }
        let name: String
        let mood: Mood
        /// True only for scenes that need a second device's NDI feed to
        /// look right (an `ndiSource` generator with nothing broadcasting
        /// to it is just black) — `AutoDirectorEngine` excludes these from
        /// its pool unless an NDI source is actually connected, and drops
        /// back out the moment it disconnects.
        var requiresNDI: Bool = false
        let make: () -> Graph
    }

    static let all: [Scene] = camera + generative + hybrid

    // MARK: - Camera-forward (the room itself is the star)

    private static let camera: [Scene] = [
        Scene(name: "Live Feed", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("vignette"),
                          .init("trails", inlineLFO: (paramID: "p0", rate: 0.05, depth: 0.3, shape: 0))],
                mods: [.init(input: "energy", targetIndex: 0)],
                macros: [.init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Vignette", routes: [(1, "p0", 0.1, 0.7)]),
                         .init("Trails", routes: [(2, "p1", 0.3, 0.9)])])
        },
        Scene(name: "Camera Twirl Live", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("chromaKey"),
                          .init("twirl", inlineLFO: (paramID: "p0", rate: 0.06, depth: 0.8, shape: 0))],
                mods: [.init(input: "bass", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Softness", routes: [(1, "p1", 0.05, 0.6)]),
                         .init("Radius", routes: [(2, "p1", 0.3, 1.3)])])
        },
        Scene(name: "Camera Datamosh Live", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("datamosh"), .init("posterize")],
                mods: [.init(input: "beatStrength", targetIndex: 1), .init(input: "sampleHold", targetIndex: 2)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Block Size", routes: [(1, "p1", 4, 40)]),
                         .init("Gamma", routes: [(2, "p1", 0.5, 2)])])
        },
        Scene(name: "Camera Glass", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("chromaticAberration"), .init("grain")],
                mods: [.init(input: "treble", targetIndex: 1)],
                macros: [.init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Falloff", routes: [(1, "p1", 0.3, 2.2)]),
                         .init("Grain", routes: [(2, "p0", 0.1, 0.6)])])
        },
        Scene(name: "Camera Grain Storm", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("grain"), .init("posterize")],
                mods: [.init(input: "beatStrength", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Grain Size", routes: [(1, "p1", 1, 6)]),
                         .init("Posterize", routes: [(2, "p0", 2, 12)])])
        },
        Scene(name: "Camera Vignette Trip", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("vignette"), .init("chromaticAberration")],
                mods: [.init(input: "energy", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Grain", routes: [(1, "p1", 0.05, 0.6)]),
                         .init("Falloff", routes: [(2, "p1", 0.3, 2.2)])])
        },
        Scene(name: "Camera Feedback Ghost", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("feedback")],
                mods: [.init(input: "bass", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Feedback Zoom", routes: [(1, "p1", 0.95, 1.05)])])
        },
        Scene(name: "Camera Video Wall", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("mosaic")],
                mods: [.init(input: "beatStrength", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Grid", routes: [(1, "p0", 2, 10)]),
                         .init("Gap", routes: [(1, "p1", 0, 0.2)])])
        },
        Scene(name: "Camera Puzzle Break", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("shuffle")],
                mods: [.init(input: "beatStrength", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Grid", routes: [(1, "p0", 2, 7)]),
                         .init("Seed", routes: [(1, "p1", 0, 1)]),
                         .init("Scramble", routes: [(1, "p2", 0.2, 1)])])
        },
        Scene(name: "Face Reveal", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("shapes", ["p1": 3])], branchB: [.init("camera")], combinerType: "mask",
                post: [.init("bloom"), .init("rotate")],
                mods: [.init(input: "faceDetected", targetIndex: 2)],
                macros: [.init("Shape Softness", routes: [(0, "p2", 0.01, 0.25)]),
                         .init("Exposure", routes: [(1, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(1, "p1", 0, 1.8)]),
                         .init("Intensity", routes: [(3, "p1", 0.3, 2.2)]),
                         .init("Spin", routes: [(4, "p0", -1.5, 1.5)])])
        },
        Scene(name: "Camera Negative", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("invert"), .init("chromaticAberration")],
                mods: [.init(input: "beatStrength", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Negative", routes: [(1, "p0", 0.3, 1)]),
                         .init("Falloff", routes: [(2, "p1", 0.3, 2.2)])])
        },
        Scene(name: "Strobe Pulse", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("strobe")],
                mods: [.init(input: "beatStrength", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Rate", routes: [(1, "p0", 2, 14)]),
                         .init("Amount", routes: [(1, "p1", 0.2, 1)]),
                         .init("Duty", routes: [(1, "p2", 0.05, 0.6)]),
                         .init("Color", routes: [(1, "p3", 0, 1)])])
        },
        Scene(name: "Camera VHS", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("vhs"), .init("scanlines")],
                mods: [.init(input: "noise", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Tracking", routes: [(1, "p0", 0.1, 0.9)]),
                         .init("Static", routes: [(1, "p1", 0.1, 0.7)]),
                         .init("Bleed", routes: [(1, "p2", 0.1, 0.8)]),
                         .init("Scan", routes: [(2, "p1", 0, 0.6)])])
        },
        Scene(name: "Old Film Reel", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("oldFilm"), .init("vignette")],
                mods: [.init(input: "envelope", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Flicker", routes: [(1, "p0", 0.1, 0.7)]),
                         .init("Scratches", routes: [(1, "p1", 0.1, 0.7)]),
                         .init("Sepia", routes: [(1, "p2", 0.2, 1)]),
                         .init("Vignette", routes: [(2, "p0", 0.2, 0.8)])])
        },
        Scene(name: "Camera Light Orb", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("lightOrb"), .init("bloom")],
                mods: [.init(input: "energy", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Orb Speed", routes: [(1, "p0", 0.4, 2.4)]),
                         .init("Edge Sense", routes: [(1, "p1", 0.2, 1)]),
                         .init("Glow Size", routes: [(1, "p2", 0.02, 0.12)]),
                         .init("Orb Palette", routes: [(1, "p3", 0, 5)]),
                         .init("Intensity", routes: [(2, "p1", 0.3, 2.2)])])
        },
        Scene(name: "Camera Follow Spot", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("spotlight"), .init("bloom")],
                mods: [.init(input: "energy", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Spot Speed", routes: [(1, "p0", 0.4, 2.4)]),
                         .init("Edge Sense", routes: [(1, "p1", 0.2, 1)]),
                         .init("Beam Size", routes: [(1, "p2", 0.03, 0.2)]),
                         .init("Softness", routes: [(1, "p3", 0.3, 2)]),
                         .init("Intensity", routes: [(2, "p1", 0.3, 2.2)])])
        },
        // Both gracefully cover the "nobody in frame" case on their own
        // (fs_faceZoom holds a gentle center zoom, fs_faceGrid passes the
        // source straight through) so, unlike the NDI scene below, neither
        // needs a `requiresNDI`-style gate to stay safe in the director's
        // ordinary rotation — whether 0, 1, 2, or 3 faces show up once this
        // scene is picked, the shader itself adapts every frame.
        Scene(name: "Face Close-Up", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("faceZoom")],
                mods: [.init(input: "faceDetected", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Padding", routes: [(1, "p0", 1.3, 3)]),
                         .init("Vertical Bias", routes: [(1, "p1", -0.25, 0.1)]),
                         .init("Fallback Zoom", routes: [(1, "p2", 1, 2.2)])])
        },
        Scene(name: "Face Spotlight", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("faceSpotlight"), .init("bloom")],
                mods: [.init(input: "energy", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Follow Speed", routes: [(1, "p0", 0.15, 0.7)]),
                         .init("Beam Size", routes: [(1, "p1", 0.05, 0.2)]),
                         .init("Softness", routes: [(1, "p2", 0.3, 2)]),
                         .init("Intensity", routes: [(2, "p1", 0.3, 2.2)])])
        },
        Scene(name: "Face Grid", mood: .camera) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera"), .init("faceGrid")],
                mods: [.init(input: "faceDetected", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Padding", routes: [(1, "p0", 1.3, 3)]),
                         .init("Gap", routes: [(1, "p1", 0, 0.04)])])
        },
        // Only ever offered to `AutoDirectorEngine` while a second
        // device's NDI feed is actually connected — see `requiresNDI`.
        Scene(name: "Two Cameras Blend", mood: .camera, requiresNDI: true) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera")], branchB: [.init("ndiSource")], combinerType: "blend",
                combinerOverrides: ["p1": 3],
                post: [.init("bloom")],
                mods: [.init(input: "lfo", targetIndex: 2)],
                macros: [.init("Exposure A", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Exposure B", routes: [(1, "p0", 0.4, 1.6)]),
                         .init("Mix", routes: [(2, "p0", 0, 1)]),
                         .init("Intensity", routes: [(3, "p1", 0.3, 2.2)])])
        },
    ]

    // MARK: - Pure generative (no camera/mic dependency — safe fallback)

    private static let generative: [Scene] = [
        Scene(name: "Plasma Drift", mood: .generative) {
            GraphTemplateCatalog.build(
                branchA: [.init("plasma", inlineLFO: (paramID: "p2", rate: 0.03, depth: 0.5, shape: 0)),
                          .init("hueRotate", inlineLFO: (paramID: "p0", rate: 0.02, depth: 1.0, shape: 3))],
                mods: [.init(input: "lfo", targetIndex: 0)],
                macros: [.init("Speed", routes: [(0, "p1", 0.2, 2.2)]),
                         .init("Palette", routes: [(0, "p3", 0, 5)]),
                         .init("Saturation", routes: [(1, "p1", 0, 1.8)])])
        },
        Scene(name: "Flow Field Calm", mood: .generative) {
            GraphTemplateCatalog.build(
                branchA: [.init("flowField"), .init("bloom")],
                mods: [.init(input: "lfo", targetIndex: 0), .init(input: "energy", targetIndex: 1)],
                macros: [.init("Speed", routes: [(0, "p1", 0.2, 2.2)]),
                         .init("Palette", routes: [(0, "p3", 0, 5)]),
                         .init("Threshold", routes: [(1, "p0", 0.2, 0.8)])])
        },
        Scene(name: "Voronoi Bloom", mood: .generative) {
            GraphTemplateCatalog.build(
                branchA: [.init("voronoi"), .init("blur"), .init("bloom")],
                mods: [.init(input: "mid", targetIndex: 0)],
                macros: [.init("Edge", routes: [(0, "p2", 1, 6)]),
                         .init("Palette", routes: [(0, "p3", 0, 5)]),
                         .init("Blur", routes: [(1, "p0", 0, 0.7)]),
                         .init("Intensity", routes: [(2, "p1", 0.3, 2.2)])])
        },
        Scene(name: "Starfield Cruise", mood: .generative) {
            GraphTemplateCatalog.build(
                branchA: [.init("starfield"), .init("bloom")],
                mods: [.init(input: "treble", targetIndex: 0), .init(input: "bass", targetIndex: 1)],
                macros: [.init("Density", routes: [(0, "p1", 60, 320)]),
                         .init("Streak", routes: [(0, "p2", 0, 1.5)]),
                         .init("Palette", routes: [(0, "p3", 0, 5)]),
                         .init("Intensity", routes: [(1, "p1", 0.4, 2.5)])])
        },
        Scene(name: "Line Art Waves", mood: .generative) {
            GraphTemplateCatalog.build(
                branchA: [.init("lineArt"), .init("vignette")],
                mods: [.init(input: "mid", targetIndex: 0)],
                macros: [.init("Speed", routes: [(0, "p1", 0.2, 2.2)]),
                         .init("Wobble", routes: [(0, "p2", 0.2, 1.5)]),
                         .init("Palette", routes: [(0, "p3", 0, 5)])])
        },
        Scene(name: "Rings Pulse", mood: .generative) {
            GraphTemplateCatalog.build(
                branchA: [.init("rings"), .init("hueRotate")],
                mods: [.init(input: "bass", targetIndex: 0)],
                macros: [.init("Speed", routes: [(0, "p1", 0.2, 2.2)]),
                         .init("Thickness", routes: [(0, "p2", 0.05, 0.35)]),
                         .init("Rotation", routes: [(1, "p0", 0, 1)]),
                         .init("Saturation", routes: [(1, "p1", 0, 1.8)])])
        },
        Scene(name: "Shapes Pulse Solo", mood: .generative) {
            GraphTemplateCatalog.build(
                branchA: [.init("shapes"), .init("bloom")],
                mods: [.init(input: "bass", targetIndex: 0)],
                macros: [.init("Shape", routes: [(0, "p1", 0, 4)]),
                         .init("Softness", routes: [(0, "p2", 0.01, 0.25)]),
                         .init("Palette", routes: [(0, "p3", 0, 5)]),
                         .init("Intensity", routes: [(1, "p1", 0.3, 2.5)])])
        },
        Scene(name: "Matrix Cascade Calm", mood: .generative) {
            GraphTemplateCatalog.build(
                branchA: [.init("matrixRain"), .init("scanlines")],
                mods: [.init(input: "clock", targetIndex: 0)],
                macros: [.init("Glyph Size", routes: [(0, "p2", 0.03, 0.2)]),
                         .init("Palette", routes: [(0, "p3", 0, 5)]),
                         .init("Scan", routes: [(1, "p1", 0, 0.7)])])
        },
        Scene(name: "Fractal Drift", mood: .generative) {
            GraphTemplateCatalog.build(
                branchA: [.init("fractal"), .init("hueRotate")],
                mods: [.init(input: "noise", targetIndex: 0)],
                macros: [.init("Mode", routes: [(0, "p2", 0, 4)]),
                         .init("Detail", routes: [(0, "p1", 0.5, 2.2)]),
                         .init("Palette", routes: [(0, "p3", 0, 5)]),
                         .init("Saturation", routes: [(1, "p1", 0, 1.8)])])
        },
        Scene(name: "Particle Field", mood: .generative) {
            GraphTemplateCatalog.build(
                branchA: [.init("particles"), .init("bloom")],
                mods: [.init(input: "beatStrength", targetIndex: 0)],
                macros: [.init("Speed", routes: [(0, "p1", 0.3, 3.2)]),
                         .init("Size", routes: [(0, "p2", 0.2, 1.6)]),
                         .init("Palette", routes: [(0, "p3", 0, 5)]),
                         .init("Intensity", routes: [(1, "p1", 0.3, 2.5)])])
        },
    ]

    // MARK: - Hybrid (camera blended with a generative texture)

    private static let hybrid: [Scene] = [
        Scene(name: "Camera + Plasma", mood: .hybrid) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera")], branchB: [.init("plasma")], combinerType: "blend",
                combinerOverrides: ["p1": 3],
                post: [.init("bloom")],
                mods: [.init(input: "energy", targetIndex: 2), .init(input: "lfo", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Plasma Scale", routes: [(1, "p2", 1, 4)]),
                         .init("Palette", routes: [(1, "p3", 0, 5)]),
                         .init("Intensity", routes: [(3, "p1", 0.3, 2.2)])])
        },
        Scene(name: "Camera Displace Fractal", mood: .hybrid) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera")], branchB: [.init("fractal", ["p2": 0])], combinerType: "displace",
                post: [.init("vignette")],
                mods: [.init(input: "noise", targetIndex: 2)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Fractal Zoom", routes: [(1, "p0", 0.5, 3.5)]),
                         .init("Detail", routes: [(1, "p1", 0.5, 2)]),
                         .init("Vignette", routes: [(3, "p0", 0.1, 0.6)])])
        },
        Scene(name: "Camera Luma Kaleido", mood: .hybrid) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera")], branchB: [.init("kaleido")], combinerType: "lumaKey",
                mods: [.init(input: "envelope", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Kaleido Zoom", routes: [(1, "p2", 0.3, 2.2)]),
                         .init("Threshold", routes: [(2, "p0", 0.2, 0.8)])])
        },
        Scene(name: "Camera Kaleido Mix", mood: .hybrid) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera")], branchB: [.init("flowField")], combinerType: "kaleidoMix",
                post: [.init("bloom")],
                mods: [.init(input: "beatStrength", targetIndex: 2), .init(input: "energy", targetIndex: 0)],
                macros: [.init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Flow Speed", routes: [(1, "p1", 0.2, 2.2)]),
                         .init("Mix", routes: [(2, "p1", 0.2, 0.8)]),
                         .init("Intensity", routes: [(3, "p1", 0.3, 2.2)])])
        },
        Scene(name: "Camera Wipe Plasma", mood: .hybrid) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera")], branchB: [.init("plasma")], combinerType: "wipe",
                mods: [.init(input: "lfo", targetIndex: 2)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Plasma Scale", routes: [(1, "p2", 1, 4)]),
                         .init("Wipe Softness", routes: [(2, "p2", 0.02, 0.25)])])
        },
        Scene(name: "Camera Sequenced Grid", mood: .hybrid) {
            GraphTemplateCatalog.build(
                branchA: [.init("camera")], branchB: [.init("gridPulse")], combinerType: "blend",
                combinerOverrides: ["p1": 3],
                post: [.init("bloom")],
                mods: [.init(input: "sequencer", targetIndex: 1)],
                macros: [.init("Exposure", routes: [(0, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(0, "p1", 0, 1.8)]),
                         .init("Grid Size", routes: [(1, "p2", 4, 30)]),
                         .init("Mix", routes: [(2, "p0", 0.2, 0.8)]),
                         .init("Intensity", routes: [(3, "p1", 0.3, 2.2)])])
        },
        Scene(name: "Camera Shapes Mask", mood: .hybrid) {
            GraphTemplateCatalog.build(
                branchA: [.init("shapes", ["p1": 3])], branchB: [.init("camera")], combinerType: "mask",
                post: [.init("bloom"), .init("rotate")],
                mods: [.init(input: "energy", targetIndex: 2)],
                macros: [.init("Shape Softness", routes: [(0, "p2", 0.01, 0.25)]),
                         .init("Exposure", routes: [(1, "p0", 0.4, 1.6)]),
                         .init("Saturation", routes: [(1, "p1", 0, 1.8)]),
                         .init("Intensity", routes: [(3, "p1", 0.3, 2.2)]),
                         .init("Spin", routes: [(4, "p0", -1.5, 1.5)])])
        },
    ]
}
