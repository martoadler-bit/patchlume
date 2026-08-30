import CoreGraphics
import Foundation

/// Central catalog of every node type Patchlume ships in v1: what ports and
/// parameters it has, its default parameter values, and its display name.
/// Same role as Modula's `ModuleCatalog` — one place to add a new shader
/// without touching the canvas, inspector, or render engine's plumbing.
enum NodeCatalog {
    // MARK: - Subtype identifiers (also the Metal fragment function name suffix)

    static let generatorTypes = ["plasma", "voronoi", "tunnel", "rings", "kaleido", "starfield", "gradientFlow", "gridPulse",
                                  "fractal", "reaction", "matrixRain", "particles", "camera", "media", "text",
                                  "flowField", "lineArt", "shapes", "ndiSource"]
    static let modifierTypes = ["blur", "hueRotate", "mirror", "rgbSplit", "pixelate", "bloom", "scanlines", "feedback",
                                 "twirl", "datamosh", "posterize", "edgeDetect", "vignette", "chromaKey",
                                 "trails", "grain", "chromaticAberration", "mosaic", "shuffle", "rotate", "invert", "strobe",
                                 "vhs", "oldFilm", "lightOrb", "spotlight", "faceZoom", "faceGrid", "faceSpotlight"]
    static let combinerTypes = ["blend", "mask", "difference", "displace", "lumaKey", "beatCrossfade", "kaleidoMix", "wipe"]
    static let inputTypes = ["time", "lfo", "constant", "bass", "mid", "treble", "energy", "beatStrength", "midiCC", "midiNote",
                              "envelope", "sampleHold", "clock", "noise", "sequencer", "faceDetected"]

    static func displayName(kind: NodeKind, subtype: String) -> String {
        switch (kind, subtype) {
        case (.generator, "plasma"): return "Plasma"
        case (.generator, "voronoi"): return "Voronoi Field"
        case (.generator, "tunnel"): return "Tunnel"
        case (.generator, "rings"): return "Rings"
        case (.generator, "kaleido"): return "Kaleidoscope"
        case (.generator, "starfield"): return "Starfield"
        case (.generator, "gradientFlow"): return "Gradient Flow"
        case (.generator, "gridPulse"): return "Grid Pulse"
        case (.generator, "fractal"): return "Fractal"
        case (.generator, "reaction"): return "Reaction"
        case (.generator, "matrixRain"): return "Matrix Rain"
        case (.generator, "particles"): return "Particles"
        case (.generator, "camera"): return "Camera"
        case (.generator, "media"): return "Media"
        case (.generator, "text"): return "Text"
        case (.generator, "flowField"): return "Flow Field"
        case (.generator, "lineArt"): return "Line Art"
        case (.generator, "shapes"): return "Shapes"
        case (.generator, "ndiSource"): return "NDI Source"
        case (.modifier, "blur"): return "Blur"
        case (.modifier, "hueRotate"): return "Hue Rotate"
        case (.modifier, "mirror"): return "Mirror"
        case (.modifier, "rgbSplit"): return "RGB Split"
        case (.modifier, "pixelate"): return "Pixelate"
        case (.modifier, "bloom"): return "Bloom"
        case (.modifier, "scanlines"): return "Scanlines"
        case (.modifier, "feedback"): return "Feedback"
        case (.modifier, "twirl"): return "Twirl"
        case (.modifier, "datamosh"): return "Datamosh"
        case (.modifier, "posterize"): return "Posterize"
        case (.modifier, "edgeDetect"): return "Edge Detect"
        case (.modifier, "vignette"): return "Vignette"
        case (.modifier, "chromaKey"): return "Chroma Key"
        case (.modifier, "trails"): return "Trails"
        case (.modifier, "grain"): return "Grain"
        case (.modifier, "chromaticAberration"): return "Chromatic Aberration"
        case (.modifier, "mosaic"): return "Mosaic"
        case (.modifier, "shuffle"): return "Shuffle"
        case (.modifier, "rotate"): return "Rotate"
        case (.modifier, "invert"): return "Invert"
        case (.modifier, "strobe"): return "Strobe"
        case (.modifier, "vhs"): return "VHS"
        case (.modifier, "oldFilm"): return "Old Film"
        case (.modifier, "lightOrb"): return "Light Orb"
        case (.modifier, "spotlight"): return "Spotlight"
        case (.modifier, "faceZoom"): return "Face Close-Up"
        case (.modifier, "faceGrid"): return "Face Grid"
        case (.modifier, "faceSpotlight"): return "Face Spotlight"
        case (.combiner, "blend"): return "Blend"
        case (.combiner, "mask"): return "Mask"
        case (.combiner, "difference"): return "Difference"
        case (.combiner, "displace"): return "Displace"
        case (.combiner, "lumaKey"): return "Luma Key"
        case (.combiner, "beatCrossfade"): return "Beat Crossfade"
        case (.combiner, "kaleidoMix"): return "Kaleido Mix"
        case (.combiner, "wipe"): return "Wipe"
        case (.input, "time"): return "Time"
        case (.input, "lfo"): return "LFO"
        case (.input, "constant"): return "Constant"
        case (.input, "bass"): return "Bass"
        case (.input, "mid"): return "Mid"
        case (.input, "treble"): return "Treble"
        case (.input, "energy"): return "Energy"
        case (.input, "beatStrength"): return "Beat Strength"
        case (.input, "midiCC"): return "MIDI CC"
        case (.input, "midiNote"): return "MIDI Note"
        case (.input, "envelope"): return "Envelope"
        case (.input, "sampleHold"): return "Sample & Hold"
        case (.input, "clock"): return "Clock"
        case (.input, "noise"): return "Noise"
        case (.input, "sequencer"): return "Sequencer"
        case (.input, "faceDetected"): return "Face"
        case (.output, _): return "Output"
        default: return subtype.capitalized
        }
    }

    static func ports(kind: NodeKind) -> (inputs: [PortDescriptor], outputs: [PortDescriptor]) {
        switch kind {
        case .generator:
            return ([PortDescriptor(id: "mod", label: "mod", signalType: .value)],
                     [PortDescriptor(id: "out", label: "out", signalType: .texture)])
        case .modifier:
            return ([PortDescriptor(id: "in", label: "in", signalType: .texture),
                      PortDescriptor(id: "mod", label: "mod", signalType: .value)],
                     [PortDescriptor(id: "out", label: "out", signalType: .texture)])
        case .combiner:
            return ([PortDescriptor(id: "inA", label: "A", signalType: .texture),
                      PortDescriptor(id: "inB", label: "B", signalType: .texture)],
                     [PortDescriptor(id: "out", label: "out", signalType: .texture)])
        case .output:
            return ([PortDescriptor(id: "in", label: "in", signalType: .texture)], [])
        case .input:
            return ([], [PortDescriptor(id: "out", label: "out", signalType: .value)])
        }
    }

    /// Parameters for a given (kind, subtype). p0...p3 map directly onto the
    /// shared Uniforms slots the shader reads; the first float parameter of
    /// generators/modifiers is flagged as the primary modulation target so
    /// an Input node's cable has an obvious, single place to land.
    static func parameters(kind: NodeKind, subtype: String) -> [ParameterDescriptor] {
        switch kind {
        case .generator:
            switch subtype {
            case "plasma": return [
                p("p0", "Complexity", 1, 8, 3, primary: true),
                p("p1", "Speed", 0, 3, 1),
                p("p2", "Scale", 0.5, 6, 2),
                p("p3", "Palette", 0, 5, 0)]
            case "voronoi": return [
                p("p0", "Cell Count", 2, 30, 10, primary: true),
                p("p1", "Speed", 0, 3, 0.6),
                p("p2", "Edge Sharpness", 0.5, 8, 3),
                p("p3", "Palette", 0, 5, 1)]
            case "tunnel": return [
                p("p0", "Speed", 0, 5, 1.5, primary: true),
                p("p1", "Twist", 0, 6, 1),
                p("p2", "Rings", 2, 40, 12),
                p("p3", "Palette", 0, 5, 2)]
            case "rings": return [
                p("p0", "Density", 1, 40, 10, primary: true),
                p("p1", "Speed", 0, 3, 1),
                p("p2", "Thickness", 0.02, 0.5, 0.15),
                p("p3", "Palette", 0, 5, 3)]
            case "kaleido": return [
                p("p0", "Segments", 2, 24, 8, primary: true),
                p("p1", "Speed", 0, 3, 0.8),
                p("p2", "Zoom", 0.2, 4, 1),
                p("p3", "Palette", 0, 5, 4)]
            case "starfield": return [
                p("p0", "Speed", 0, 8, 2, primary: true),
                p("p1", "Density", 20, 400, 140),
                p("p2", "Streak", 0, 2, 0.4),
                p("p3", "Palette", 0, 5, 0)]
            case "gradientFlow": return [
                p("p0", "Flow Speed", 0, 3, 0.8),
                p("p1", "Turbulence", 0, 4, 1.2, primary: true),
                p("p2", "Scale", 0.5, 6, 1.6),
                p("p3", "Palette", 0, 5, 5)]
            case "gridPulse": return [
                p("p0", "Pulse Amount", 0, 4, 1.2, primary: true),
                p("p1", "Speed", 0, 4, 1),
                p("p2", "Grid Size", 2, 40, 14),
                p("p3", "Palette", 0, 5, 2)]
            case "fractal": return [
                p("p0", "Dive Depth", 0.3, 8, 3, primary: true),
                p("p1", "Detail", 0.3, 3, 1),
                p("p2", "Mode", 0, 4, 0, type: .enumType, options: ["Mandelbrot", "Julia", "Burning Ship", "Tricorn", "Multibrot"]),
                p("p3", "Palette", 0, 5, 4)]
            case "reaction": return [
                p("p0", "Growth", 0, 2, 1, primary: true),
                p("p1", "Speed", 0.1, 3, 1),
                p("p2", "Seed Rate", 0, 1, 0.4),
                p("p3", "Palette", 0, 5, 2)]
            case "matrixRain": return [
                p("p0", "Speed", 0.2, 6, 2, primary: true),
                p("p1", "Density", 10, 80, 34),
                p("p2", "Glyph Size", 0.02, 0.3, 0.06),
                p("p3", "Palette", 0, 5, 2)]
            case "particles": return [
                p("p0", "Count", 4, 160, 60, primary: true),
                p("p1", "Speed", 0, 4, 1),
                p("p2", "Size", 0.1, 2, 1),
                p("p3", "Palette", 0, 5, 0)]
            case "camera": return [
                p("p0", "Exposure", 0.2, 2, 1, primary: true),
                p("p1", "Saturation", 0, 2, 1),
                p("p2", "Lens", 0, 2, 1, type: .enumType, options: ["Front", "Back", "Back Ultra Wide"])]
            case "media": return [
                p("p0", "Exposure", 0.2, 2, 1, primary: true),
                p("p1", "Saturation", 0, 2, 1)]
            case "text": return [
                p("p0", "Scale", 0.1, 1.5, 1, primary: true),
                p("p1", "Scroll Speed", -4, 4, 0.6),
                p("p2", "Font", 0, 5, 0, type: .enumType, options: TextTextureEngine.fontNames),
                p("p3", "Palette", 0, 5, 0)]
            case "flowField": return [
                p("p0", "Density", 1, 10, 4, primary: true),
                p("p1", "Speed", 0, 3, 0.8),
                p("p2", "Turbulence", 0, 3, 1.2),
                p("p3", "Palette", 0, 5, 1)]
            case "lineArt": return [
                p("p0", "Density", 2, 40, 14, primary: true),
                p("p1", "Speed", 0, 3, 0.6),
                p("p2", "Wobble", 0, 2, 0.6),
                p("p3", "Palette", 0, 5, 3)]
            case "shapes": return [
                p("p0", "Size", 0.05, 1.5, 0.6, primary: true),
                p("p1", "Shape", 0, 4, 0, type: .enumType, options: ["Circle", "Square", "Triangle", "Ring", "Stripes"]),
                p("p2", "Softness", 0.001, 0.3, 0.05),
                p("p3", "Palette", 0, 5, 2)]
            case "ndiSource": return [
                p("p0", "Exposure", 0.2, 2, 1, primary: true),
                p("p1", "Saturation", 0, 2, 1)]
            default: return []
            }
        case .modifier:
            switch subtype {
            case "blur": return [p("p0", "Amount", 0, 1, 0.3, primary: true), p("p1", "Quality", 1, 3, 2)]
            case "hueRotate": return [p("p0", "Rotation", 0, 1, 0.2, primary: true), p("p1", "Saturation", 0, 2, 1)]
            case "mirror": return [p("p0", "Axis", 0, 2, 0, primary: true), p("p1", "Offset", -1, 1, 0)]
            case "rgbSplit": return [p("p0", "Amount", 0, 0.1, 0.02, primary: true), p("p1", "Angle", 0, 6.28, 0)]
            case "pixelate": return [p("p0", "Cell Size", 1, 64, 8, primary: true)]
            case "bloom": return [p("p0", "Threshold", 0, 1, 0.6), p("p1", "Intensity", 0, 3, 1.2, primary: true)]
            case "scanlines": return [p("p0", "Density", 40, 800, 240, primary: true), p("p1", "Intensity", 0, 1, 0.35)]
            case "feedback": return [p("p0", "Decay", 0, 0.98, 0.85, primary: true), p("p1", "Zoom", 0.9, 1.1, 1.01)]
            case "twirl": return [p("p0", "Strength", -3, 3, 1.5, primary: true), p("p1", "Radius", 0.2, 1.5, 0.8)]
            case "datamosh": return [p("p0", "Amount", 0, 1, 0.35, primary: true), p("p1", "Block Size", 2, 64, 12)]
            case "posterize": return [p("p0", "Levels", 2, 16, 5, primary: true), p("p1", "Gamma", 0.3, 3, 1)]
            case "edgeDetect": return [p("p0", "Threshold", 0, 1, 0.25, primary: true), p("p1", "Mix", 0, 1, 1)]
            case "vignette": return [p("p0", "Amount", 0, 1, 0.5, primary: true), p("p1", "Grain", 0, 1, 0.15)]
            case "chromaKey": return [p("p0", "Threshold", 0, 1, 0.4, primary: true), p("p1", "Softness", 0, 1, 0.2)]
            case "trails": return [p("p0", "Decay", 0, 0.98, 0.85, primary: true), p("p1", "Amount", 0, 1, 0.8)]
            case "grain": return [p("p0", "Amount", 0, 1, 0.3, primary: true), p("p1", "Size", 0.5, 8, 2)]
            case "chromaticAberration": return [p("p0", "Amount", 0, 0.05, 0.015, primary: true), p("p1", "Falloff", 0.1, 3, 1.5)]
            case "mosaic": return [p("p0", "Grid Size", 2, 20, 4, primary: true), p("p1", "Gap", 0, 0.3, 0.05)]
            case "shuffle": return [
                p("p0", "Grid Size", 2, 10, 4, primary: true),
                p("p1", "Seed", 0, 1, 0.3),
                p("p2", "Amount", 0, 1, 0.7)]
            case "rotate": return [
                p("p0", "Speed", -2, 2, 0.4, primary: true),
                p("p1", "Angle Offset", 0, 6.28, 0)]
            case "invert": return [p("p0", "Amount", 0, 1, 1, primary: true)]
            case "strobe": return [
                p("p0", "Rate", 0.5, 20, 6, primary: true),
                p("p1", "Amount", 0, 1, 0.8),
                p("p2", "Duty", 0.05, 0.95, 0.15),
                p("p3", "Color", 0, 1, 1)]
            case "vhs": return [
                p("p0", "Tracking", 0, 1, 0.4, primary: true),
                p("p1", "Noise", 0, 1, 0.3),
                p("p2", "Color Bleed", 0, 1, 0.3),
                p("p3", "Speed", 0, 3, 1)]
            case "oldFilm": return [
                p("p0", "Flicker", 0, 1, 0.3, primary: true),
                p("p1", "Scratches", 0, 1, 0.4),
                p("p2", "Sepia", 0, 1, 0.5),
                p("p3", "Speed", 0, 3, 1)]
            case "lightOrb": return [
                p("p0", "Speed", 0, 3, 1.2, primary: true),
                p("p1", "Edge Sensitivity", 0, 1, 0.6),
                p("p2", "Glow Size", 0.01, 0.2, 0.05),
                p("p3", "Palette", 0, 5, 1)]
            case "spotlight": return [
                p("p0", "Speed", 0, 3, 1.2, primary: true),
                p("p1", "Edge Sensitivity", 0, 1, 0.6),
                p("p2", "Beam Size", 0.01, 0.3, 0.08),
                p("p3", "Softness", 0.2, 3, 1)]
            case "faceZoom": return [
                p("p0", "Padding", 1, 4, 1.8, primary: true),
                p("p1", "Vertical Bias", -0.3, 0.3, -0.1),
                p("p2", "Fallback Zoom", 1, 3, 1.4)]
            case "faceGrid": return [
                p("p0", "Padding", 1, 4, 1.8, primary: true),
                p("p1", "Gap", 0, 0.06, 0.015)]
            case "faceSpotlight": return [
                p("p0", "Follow Speed", 0.05, 1, 0.35, primary: true),
                p("p1", "Beam Size", 0.01, 0.3, 0.1),
                p("p2", "Softness", 0.2, 3, 1)]
            default: return []
            }
        case .combiner:
            switch subtype {
            case "blend": return [p("p0", "Mix", 0, 1, 0.5, primary: false), p("p1", "Mode", 0, 3, 0, type: .enumType, options: ["Add", "Screen", "Multiply", "Mix"])]
            case "mask": return [p("p0", "Threshold", 0, 1, 0.5, primary: false)]
            case "difference": return [p("p0", "Amount", 0, 1, 1, primary: false)]
            case "displace": return [p("p0", "Amount", 0, 1, 0.5), p("p1", "Scale", 0.5, 3, 1)]
            case "lumaKey": return [p("p0", "Threshold", 0, 1, 0.5), p("p1", "Softness", 0, 1, 0.2)]
            case "beatCrossfade": return [p("p0", "Threshold", 0, 1, 0.5), p("p1", "Softness", 0, 1, 0.25)]
            case "kaleidoMix": return [p("p0", "Segments", 2, 16, 6), p("p1", "Mix", 0, 1, 0.5)]
            case "wipe": return [p("p0", "Position", 0, 1, 0.5), p("p1", "Angle", 0, 6.28, 0), p("p2", "Softness", 0.001, 0.3, 0.05)]
            default: return []
            }
        case .input:
            switch subtype {
            case "time": return []
            case "lfo": return [p("p0", "Rate", 0.05, 8, 1), p("p1", "Shape", 0, 3, 0, type: .enumType, options: ["Sine", "Triangle", "Square", "Saw"])]
            case "constant": return [p("p0", "Value", 0, 1, 0.5)]
            case "midiCC": return [p("p0", "CC Number", 0, 127, 1, type: .int)]
            case "midiNote": return [p("p0", "Channel", 0, 16, 0, type: .int)]
            case "envelope": return [
                p("p0", "Attack", 0.01, 1, 0.15),
                p("p1", "Release", 0.01, 1, 0.35),
                p("p2", "Source", 0, 3, 0, type: .enumType, options: ["Energy", "Bass", "Mid", "Treble"])]
            case "sampleHold": return [p("p0", "Rate", 0.1, 8, 2)]
            case "clock": return [
                p("p0", "BPM", 40, 240, 120),
                p("p1", "Division", 0, 4, 2, type: .enumType, options: ["1/1", "1/2", "1/4", "1/8", "1/16"])]
            case "noise": return [p("p0", "Rate", 0.05, 4, 0.5)]
            case "sequencer": return [
                p("p0", "Steps", 2, 16, 8, type: .int),
                p("p1", "BPM", 40, 240, 120),
                p("p2", "Division", 0, 4, 2, type: .enumType, options: ["1/1", "1/2", "1/4", "1/8", "1/16"])]
            default: return []
            }
        case .output:
            return []
        }
    }

    private static func p(_ id: String, _ label: String, _ min: Float, _ max: Float, _ def: Float, primary: Bool = false, type: ParamType = .float, options: [String] = []) -> ParameterDescriptor {
        ParameterDescriptor(id: id, label: label, type: type, minValue: min, maxValue: max, defaultValue: def, unit: "", options: options, isPrimaryModulationTarget: primary)
    }

    static func defaultParameters(kind: NodeKind, subtype: String) -> [String: Float] {
        var result: [String: Float] = [:]
        for parameter in parameters(kind: kind, subtype: subtype) {
            result[parameter.id] = parameter.defaultValue
        }
        return result
    }

    static func makeNode(kind: NodeKind, subtype: String, position: CGPoint) -> GraphNode {
        GraphNode(kind: kind, subtype: subtype, position: position, parameters: defaultParameters(kind: kind, subtype: subtype),
                  textContent: subtype == "text" ? "PATCHLUME" : nil)
    }
}
