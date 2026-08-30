import Foundation

/// An LFO attached directly to one parameter, no cable or Input node
/// needed — long-press a knob to add one. Distinct from the single cable-
/// based "mod" port (which still exists, targets only a node's primary
/// parameter, and is meant for live Inputs like audio/MIDI): this can land
/// on ANY parameter, and several can run at once across a node. Same
/// shape/rate/depth idea as the LFO Input node's own math, just evaluated
/// per-parameter instead of through a port.
struct ParamModulator: Codable, Equatable {
    var rate: Float = 1        // Hz
    var depth: Float = 0.3     // 0...1, fraction of the parameter's own min...max range
    var shape: Int = 0         // 0 sine, 1 triangle, 2 square, 3 saw — matches the LFO Input's convention
}

/// A performance knob: one live 0...1 value the user rides while watching
/// the preview (see `MacroControlPanelView`), fanned out to any number of
/// (node, parameter) pairs via `MacroAssignment`. Part of the graph itself
/// (saved/undone with it), since a macro rig is as much "the patch" as the
/// nodes and cables are.
struct Macro: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var value: Float

    init(id: UUID = UUID(), name: String, value: Float = 0.5) {
        self.id = id
        self.name = name
        self.value = value
    }
}

/// One routed connection: `macroID` at 0 sets `nodeID`'s `paramID` to
/// `rangeMin`, at 1 sets it to `rangeMax`, linearly in between — an actual
/// value mapping (a macro at 0.5 always reads as exactly the midpoint),
/// not an offset added on top of whatever the knob is dialed to. Both
/// bounds are in the parameter's own real units (not normalized 0...1), so
/// "10 to 50" means literally that regardless of the parameter's declared
/// min...max. `rangeMin > rangeMax` inverts the sweep — turning the macro
/// up moves the parameter down — for free, with no separate invert flag.
struct MacroAssignment: Identifiable, Codable, Equatable {
    let id: UUID
    var macroID: UUID
    var nodeID: UUID
    var paramID: String
    var rangeMin: Float
    var rangeMax: Float

    init(id: UUID = UUID(), macroID: UUID, nodeID: UUID, paramID: String, rangeMin: Float, rangeMax: Float) {
        self.id = id
        self.macroID = macroID
        self.nodeID = nodeID
        self.paramID = paramID
        self.rangeMin = rangeMin
        self.rangeMax = rangeMax
    }
}

/// Shared -1...1 waveform math for both the inline `ParamModulator` and the
/// LFO Input node, so the two stay visually/behaviorally identical.
func lfoWaveform(phase: Float, shape: Int) -> Float {
    let p = phase.truncatingRemainder(dividingBy: 1)
    switch shape {
    case 1: return 1 - 2 * abs(2 * p - 1)      // triangle
    case 2: return p < 0.5 ? 1 : -1            // square
    case 3: return p * 2 - 1                   // saw
    default: return sin(p * 2 * .pi)           // sine
    }
}
