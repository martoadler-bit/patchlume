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
    /// Live face tracking from `CameraCaptureEngine`, not a per-node
    /// parameter — same "always-available environment data" category as
    /// `time`/`resolution` rather than a knob, since up to 3 dynamic face
    /// positions don't fit in the 4-slot p0...p3 budget every node already
    /// spends on its own controls. `faceN.xy` = center, `.zw` = half-size,
    /// all normalized 0...1; unused slots (beyond `faceCount`) are zero.
    var faceCount: Float = 0
    var face0: SIMD4<Float> = .zero
    var face1: SIMD4<Float> = .zero
    var face2: SIMD4<Float> = .zero
}
