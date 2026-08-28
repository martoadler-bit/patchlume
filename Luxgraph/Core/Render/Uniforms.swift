import simd

/// Shared per-draw uniform buffer, written once per pass from Swift and read
/// by every generator/modifier/combiner fragment shader. Field order and
/// types must stay in lockstep with the `Uniforms` struct declared in
/// `Shaders.metal` — both sides use only `Float`/`float2`, so there's no
/// std140-style padding surprise to worry about, but the order still has to
/// match exactly since there is no shared header (no bridging header is
/// needed for a from-scratch Metal project like this one).
struct Uniforms {
    var time: Float = 0
    var beat: Float = 0
    var beatStrength: Float = 0
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var energy: Float = 0
    var modValue: Float = 0
    var p0: Float = 0
    var p1: Float = 0
    var p2: Float = 0
    var p3: Float = 0
    var resolution: SIMD2<Float> = .zero
    var _pad: SIMD2<Float> = .zero
}
