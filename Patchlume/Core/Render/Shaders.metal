#include <metal_stdlib>
using namespace metal;

// Must match Core/Render/Uniforms.swift field-for-field.
struct Uniforms {
    float time;
    float beat;
    float beatStrength;
    float bass;
    float mid;
    float treble;
    float energy;
    float modValue;
    float p0;
    float p1;
    float p2;
    float p3;
    float2 resolution;
    float2 _pad;
    // Live face tracking, not a per-node parameter — see Uniforms.swift.
    float faceCount;
    float4 face0;
    float4 face1;
    float4 face2;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Fullscreen triangle, no vertex buffer needed.
vertex VertexOut vs_main(uint vid [[vertex_id]]) {
    float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VertexOut out;
    float2 p = positions[vid];
    out.position = float4(p, 0, 1);
    out.uv = float2((p.x + 1) * 0.5, 1.0 - (p.y + 1) * 0.5);
    return out;
}

// ---------- shared helpers ----------

static float hash21(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

static float2 hash22(float2 p) {
    float n = sin(dot(p, float2(41, 289)));
    return fract(float2(262144, 32768) * n);
}

static float noise2(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Six IQ-style cosine palettes (a + b*cos(2pi*(c*t+d))), continuously
// cross-faded by the fractional part of `index` so the Palette slider (a
// plain 0...5 float, not a stepped enum) always looks alive while dragging
// instead of hard-cutting between themes.
static float3 paletteAt(float t, int idx) {
    float3 a = float3(0.5, 0.5, 0.5);
    float3 b = float3(0.5, 0.5, 0.5);
    float3 c = float3(1.0, 1.0, 1.0);
    float3 d = float3(0.0, 0.33, 0.67);
    if (idx == 0) { d = float3(0.0, 0.10, 0.20); }
    else if (idx == 1) { d = float3(0.30, 0.20, 0.20); c = float3(1.0, 0.7, 0.4); }
    else if (idx == 2) { d = float3(0.80, 0.90, 0.30); b = float3(0.2, 0.4, 0.2); }
    else if (idx == 3) { d = float3(0.0, 0.15, 0.20); c = float3(1.2, 1.0, 0.0); }
    else if (idx == 4) { d = float3(0.30, 0.20, 0.50); }
    else { d = float3(0.60, 0.10, 0.30); }
    return a + b * cos(6.28318 * (c * t + d));
}

static float3 palette(float t, float index) {
    float clampedIndex = clamp(index, 0.0, 5.0);
    int lo = int(floor(clampedIndex));
    int hi = min(lo + 1, 5);
    float3 colorLo = paletteAt(t, lo);
    float3 colorHi = paletteAt(t, hi);
    return mix(colorLo, colorHi, fract(clampedIndex));
}

// Gentle Reinhard-style tonemap so additive glow (bloom, starfield) rolls off
// softly toward white instead of hard-clipping into flat plateaus.
static float3 tonemap(float3 c) {
    return c / (1.0 + max(max(c.r, c.g), c.b) * 0.35);
}

// Signed-distance primitives for fs_shapes — negative inside the shape,
// positive outside, magnitude = distance to the edge, so one shared
// smoothstep(0, softness, d) turns any of them into a soft/hard mask.
static float sdCircle(float2 p, float r) {
    return length(p) - r;
}

static float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

static float sdTriangle(float2 p, float r) {
    const float k = 1.7320508; // sqrt(3)
    p.x = abs(p.x) - r;
    p.y = p.y + r / k;
    if (p.x + k * p.y > 0.0) { p = float2(p.x - k * p.y, -k * p.x - p.y) * 0.5; }
    p.x -= clamp(p.x, -2.0 * r, 0.0);
    return -length(p) * sign(p.y);
}

static float3x3 rotZ(float a) {
    float s = sin(a), c = cos(a);
    return float3x3(float3(c, -s, 0), float3(s, c, 0), float3(0, 0, 1));
}

// Shared by every pass that samples a source texture (modifiers, combiners,
// the two self-feeding generators, present) — declared once up here so the
// generators section below can use it too.
constexpr sampler modSampler(coord::normalized, address::clamp_to_edge, filter::linear);
// Horizontal-repeat variant used by fs_text's scrolling marquee — wraps
// instead of clamping so the UV offset can run unbounded with time.
constexpr sampler repeatSampler(coord::normalized, address::repeat, filter::linear);

// ---------- generators ----------
// Each generator reads u.modValue (0...1, driven by whatever Input node is
// patched into its "mod" port, or 0 if nothing is patched) added onto p0,
// so modulation always pushes the primary parameter upward from wherever
// it's dialed.

fragment float4 fs_plasma(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = (in.uv - 0.5) * float2(u.resolution.x / max(u.resolution.y, 1.0), 1.0) * u.p2;
    float complexity = u.p0 + u.modValue * 6.0;
    float t = u.time * (0.3 + u.p1);
    float v = 0.0;
    for (float i = 1.0; i <= 4.0; i += 1.0) {
        v += sin(uv.x * complexity * i + t) * 0.5;
        v += cos(uv.y * complexity * i - t * 1.3) * 0.5;
        uv += float2(uv.y, -uv.x) * 0.15;
    }
    v = v * 0.25 + 0.5;
    return float4(palette(v, u.p3), 1.0);
}

fragment float4 fs_voronoi(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float cells = u.p0 + u.modValue * 20.0;
    float2 uv = in.uv * cells;
    float2 t = float2(u.time * u.p1, u.time * u.p1 * 0.7);
    float2 i = floor(uv);
    float minDist = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = float2(float(x), float(y));
            float2 point = hash22(i + neighbor) * 0.5 + 0.5;
            point = 0.5 + 0.5 * sin(t + 6.28318 * point);
            float2 diff = neighbor + point - fract(uv);
            minDist = min(minDist, length(diff));
        }
    }
    float edge = pow(1.0 - saturate(minDist), u.p2);
    return float4(palette(edge, u.p3), 1.0);
}

fragment float4 fs_tunnel(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = (in.uv - 0.5) * float2(u.resolution.x / max(u.resolution.y, 1.0), 1.0);
    float speed = u.p0 + u.modValue * 4.0;
    float angle = atan2(uv.y, uv.x) + u.time * u.p1 * 0.3;
    float radius = length(uv) + 0.0001;
    float depth = u.p2 / radius + u.time * speed;
    float rings = fract(depth);
    float glow = smoothstep(0.0, 0.5, rings) * smoothstep(1.0, 0.5, rings);
    float shade = glow * (0.6 + 0.4 * sin(angle * 4.0));
    return float4(palette(fract(depth * 0.1), u.p3) * shade + 0.02, 1.0);
}

fragment float4 fs_rings(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = (in.uv - 0.5) * float2(u.resolution.x / max(u.resolution.y, 1.0), 1.0);
    float density = u.p0 + u.modValue * 20.0;
    float r = length(uv);
    float wave = sin(r * density - u.time * (1.0 + u.p1) * 3.0);
    float band = smoothstep(u.p2, 0.0, abs(wave));
    return float4(palette(r + u.time * 0.05, u.p3) * band, 1.0);
}

fragment float4 fs_kaleido(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = (in.uv - 0.5) * float2(u.resolution.x / max(u.resolution.y, 1.0), 1.0);
    float segments = max(2.0, u.p0 + u.modValue * 12.0);
    float angle = atan2(uv.y, uv.x);
    float radius = length(uv) * u.p2;
    float wedge = 6.28318 / segments;
    angle = abs(fmod(angle + u.time * u.p1 * 0.4, wedge) - wedge * 0.5);
    float2 kuv = float2(cos(angle), sin(angle)) * radius;
    float v = noise2(kuv * 3.0 + u.time * 0.2);
    return float4(palette(v + radius * 0.1, u.p3), 1.0);
}

fragment float4 fs_starfield(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = (in.uv - 0.5) * float2(u.resolution.x / max(u.resolution.y, 1.0), 1.0);
    float speed = u.p0 + u.modValue * 6.0;
    float density = u.p1;
    float3 color = float3(0.0);
    for (float i = 0.0; i < 3.0; i += 1.0) {
        float layer = i + 1.0;
        float2 grid = uv * (density / layer) ;
        float2 id = floor(grid);
        float2 f = fract(grid) - 0.5;
        float star = hash21(id + layer * 13.1);
        float z = fract(star * 4.0 + u.time * speed * 0.2 * layer);
        float size = (1.0 - z) * 0.06;
        float d = length(f);
        float glow = smoothstep(size, 0.0, d) * (1.0 - z);
        color += glow * (0.5 + 0.5 * u.p2);
    }
    return float4(tonemap(palette(0.5, u.p3) * color + color * 0.3), 1.0);
}

fragment float4 fs_gradientFlow(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = in.uv * u.p2;
    float turbulence = u.p1 + u.modValue * 3.0;
    float t = u.time * (0.2 + u.p0);
    float n = noise2(uv + t) * turbulence;
    n += noise2(uv * 2.0 - t * 1.5) * 0.5;
    return float4(palette(n * 0.3 + t * 0.05, u.p3), 1.0);
}

fragment float4 fs_gridPulse(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float gridSize = u.p2;
    float2 uv = in.uv * gridSize;
    float2 cell = fract(uv) - 0.5;
    float2 id = floor(uv);
    float pulse = u.p0 + u.modValue * 4.0;
    float phase = sin(u.time * (1.0 + u.p1) - length(id) * 0.4) * 0.5 + 0.5;
    float d = length(cell);
    float shape = smoothstep(0.45 * phase * pulse * 0.5 + 0.05, 0.0, d);
    return float4(palette(phase, u.p3) * shape, 1.0);
}

// Five escape-time fractal families sharing one loop (Mode selects which):
// 0 Mandelbrot, 1 Julia, 2 Burning Ship (abs() before squaring — spiky,
// organic), 3 Tricorn (conjugate each iteration — mirrored symmetry),
// 4 Multibrot (z^3 instead of z^2 — petals instead of one cardioid).
//
// `Dive Depth` (u.p0) no longer sets a single static zoom level — it's how
// far ONE continuous, one-directional dive goes before the cycle resets.
// True infinite zoom needs arbitrary-precision math (way past what a
// real-time shader can do — float32 visibly breaks down into blocky
// banding after roughly a millionfold zoom); this fakes the sensation
// instead of solving the math: it dives continuously inward for the whole
// `diveCycle` and only resets at the very end, snapping back to zoom=1 in
// a single frame rather than visibly reversing/pulling back out first —
// since a fractal boundary looks statistically similar at any scale, that
// snap reads as a hard cut, not a rewind, and the cycle is long enough
// that a single scene (25-50s in the Auto Director) usually never lives
// to see it happen at all — for as long as anyone's actually watching, it
// really does just keep going deeper.
fragment float4 fs_fractal(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float depth = clamp(u.p0 + u.modValue * 4.0, 0.3, 9.0);
    float diveCycle = 70.0;
    float phase = fract(u.time / diveCycle); // 0 -> 1, continuously inward, then an instant reset
    float zoom = pow(2.0, phase * depth);

    float2 uv = (in.uv - 0.5) * float2(u.resolution.x / max(u.resolution.y, 1.0), 1.0) * (3.0 / zoom);
    int maxIter = int(12.0 + saturate(u.p1 / 3.0) * 40.0);
    int mode = int(u.p2 + 0.5);

    // Julia's seed wanders a slow two-frequency path instead of a fixed
    // circle — no free uniform slot left to expose it as its own
    // macro-able parameter, so this is the automatic stand-in: still
    // never repeats on any short cycle.
    float2 juliaSeed = float2(sin(u.time * 0.081) * 0.4 + cos(u.time * 0.035) * 0.15,
                               cos(u.time * 0.097) * 0.35 + sin(u.time * 0.052) * 0.15 - 0.1);

    float2 c = mode == 1 ? juliaSeed : uv;
    float2 z = mode == 1 ? uv : float2(0.0);
    int i = 0;
    for (; i < maxIter; i++) {
        float2 zz = mode == 2 ? float2(abs(z.x), abs(z.y)) : z; // Burning Ship folds into the first quadrant
        float2 sq = float2(zz.x * zz.x - zz.y * zz.y, 2.0 * zz.x * zz.y);
        if (mode == 3) { sq.y = -sq.y; } // Tricorn: conj(z)^2 == square with y negated
        if (mode == 4) { sq = float2(zz.x * sq.x - zz.y * sq.y, zz.x * sq.y + zz.y * sq.x); } // Multibrot: z^3 = z * z^2
        z = sq + c;
        if (dot(z, z) > 16.0) break;
    }
    if (i >= maxIter) return float4(0.0, 0.0, 0.0, 1.0);
    float t = float(i) / float(maxIter);
    return float4(palette(t + u.time * 0.02, u.p3), 1.0);
}

// Self-feeding cellular automaton: each pixel diffuses toward its 4
// neighbors' average from ITS OWN previous frame (bound at texture(0) by
// RenderEngine, same self-read trick as the Feedback modifier), nudged by
// `Growth` and continuously re-seeded by a little noise so it never fully
// dies out to black. The scalar field lives in the alpha channel (the RGB
// is the display color) so next frame's read gets the raw value back, not
// an already-palette-colored value.
fragment float4 fs_reaction(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> selfPrev [[texture(0)]]) {
    float2 texel = 1.0 / max(u.resolution, float2(1.0));
    float growth = u.p0 + u.modValue * 1.5;
    float seedRate = saturate(u.p2);
    float sum = 0.0;
    sum += selfPrev.sample(modSampler, in.uv + float2(texel.x, 0.0)).a;
    sum += selfPrev.sample(modSampler, in.uv - float2(texel.x, 0.0)).a;
    sum += selfPrev.sample(modSampler, in.uv + float2(0.0, texel.y)).a;
    sum += selfPrev.sample(modSampler, in.uv - float2(0.0, texel.y)).a;
    float avg = sum * 0.25;
    float value = avg + growth * (avg - 0.5) * 0.12 - 0.01;
    float seed = hash21(in.uv * u.resolution + u.time * (1.0 + u.p1) * 37.0);
    value = saturate(mix(value, seed, seedRate * 0.02));
    return float4(palette(value, u.p3) * value, value);
}

// Rough procedural matrix-rain: columns of falling "glyph" cells (blocky
// hashed noise standing in for characters) with a bright head and a fading
// trail behind it.
fragment float4 fs_matrixRain(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float density = max(4.0, u.p1);
    float speed = u.p0 + u.modValue * 5.0;
    float col = floor(in.uv.x * density);
    float colSeed = hash21(float2(col, 7.0));
    float drop = fract(colSeed * 3.0 + u.time * speed * (0.3 + colSeed));
    float cellH = max(0.01, u.p2);
    float rowF = in.uv.y / cellH;
    float row = floor(rowF);
    float rowFrac = fract(rowF);
    float dropRow = drop / cellH;
    float dist = dropRow - row;
    float trail = saturate(1.0 - dist / 18.0) * step(0.0, dist);
    float glyph = step(0.5, hash21(float2(col, row + floor(u.time * 6.0))));
    float cellShape = glyph * smoothstep(0.0, 0.15, rowFrac) * smoothstep(1.0, 0.85, rowFrac);
    float head = smoothstep(2.0, 0.0, abs(dist)) * cellShape;
    float3 color = palette(0.33, u.p3) * trail * cellShape + float3(1.0) * head;
    return float4(color, 1.0);
}

// Procedural particle field: each of up to 160 "particles" is a hashed seed
// ballistically drifting outward from center with its own looping lifetime
// — stateless (recomputed from uv/time every frame), same trick as the
// Starfield generator, just radial instead of z-depth.
fragment float4 fs_particles(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = (in.uv - 0.5) * float2(u.resolution.x / max(u.resolution.y, 1.0), 1.0);
    float count = clamp(u.p0 + u.modValue * 120.0, 4.0, 160.0);
    float speed = u.p1;
    float size = max(0.002, u.p2 * 0.05);
    float3 color = float3(0.0);
    for (float i = 0.0; i < 160.0; i += 1.0) {
        if (i >= count) break;
        float2 seed = float2(i, i * 1.37);
        float2 rand = hash22(seed);
        float life = fract(rand.x * 5.0 + u.time * (0.2 + speed * 0.5) + rand.y);
        float2 dir = normalize(rand - 0.5 + 0.001);
        float2 pos = dir * life * 1.3;
        float d = length(uv - pos);
        float glow = smoothstep(size, 0.0, d) * (1.0 - life);
        color += glow * palette(rand.x, u.p3);
    }
    return float4(tonemap(color), 1.0);
}

// Live front-camera feed as a generator. `camTex` is bound by RenderEngine
// each frame from CameraCaptureEngine's latest CVMetalTexture, or a 4x4
// black fallback texture while the camera isn't running/authorized yet —
// so this always has something valid to sample.
fragment float4 fs_camera(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> camTex [[texture(0)]]) {
    float exposure = max(0.0, u.p0 + u.modValue * 1.5);
    float sat = u.p1;
    // p2/p3 carry the camera frame's "cover" crop scale (computed in
    // RenderEngine from the live camera texture's real aspect ratio) —
    // without this a portrait camera frame gets squashed to fit the
    // working buffer's ~16:9 shape instead of cropping to fill it.
    float2 uv = (in.uv - 0.5) * float2(u.p2, u.p3) + 0.5;
    float4 c = camTex.sample(modSampler, saturate(uv));
    float lum = dot(c.rgb, float3(0.299, 0.587, 0.114));
    float3 rgb = mix(float3(lum), c.rgb, sat) * exposure;
    return float4(saturate(rgb), 1.0);
}

// Imported photo/video as a generator. `mediaTex` is bound by RenderEngine
// each frame from MediaTextureEngine (or a black fallback while nothing's
// been picked yet) — same cover-fit convention as fs_camera, with p2/p3
// likewise computed by RenderEngine from the media's real aspect ratio
// rather than declared as user-facing catalog parameters.
fragment float4 fs_media(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> mediaTex [[texture(0)]]) {
    float exposure = max(0.0, u.p0 + u.modValue * 1.5);
    float sat = u.p1;
    float2 uv = (in.uv - 0.5) * float2(u.p2, u.p3) + 0.5;
    float4 c = mediaTex.sample(modSampler, saturate(uv));
    float lum = dot(c.rgb, float3(0.299, 0.587, 0.114));
    float3 rgb = mix(float3(lum), c.rgb, sat) * exposure;
    return float4(saturate(rgb), 1.0);
}

// Another device's NDI broadcast as a generator — a second phone's camera,
// another Patchlume, OBS, Resolume. Identical cover-fit convention to
// fs_camera/fs_media: p2/p3 aren't real catalog parameters, RenderEngine
// overwrites them each frame with the crop scale computed from the NDI
// source's actual resolution (which can differ frame to frame if the
// sender changes its own output size).
fragment float4 fs_ndiSource(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> ndiTex [[texture(0)]]) {
    float exposure = max(0.0, u.p0 + u.modValue * 1.5);
    float sat = u.p1;
    float2 uv = (in.uv - 0.5) * float2(u.p2, u.p3) + 0.5;
    float4 c = ndiTex.sample(modSampler, saturate(uv));
    float lum = dot(c.rgb, float3(0.299, 0.587, 0.114));
    float3 rgb = mix(float3(lum), c.rgb, sat) * exposure;
    return float4(saturate(rgb), 1.0);
}

// Text as a generator. `textTex` is a white-on-transparent alpha mask
// rendered once (on content/font change) by TextTextureEngine; color comes
// from the palette here instead of being baked into the CPU texture, and
// horizontal scroll is a pure UV-offset repeat-sample, so both `Scale`
// (u.p0, modulatable) and `Palette` (u.p3) can ride a macro/LFO for free
// without ever touching the CPU rasterizer.
fragment float4 fs_text(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> textTex [[texture(0)]]) {
    float scale = max(0.05, u.p0 + u.modValue * 0.8);
    float scroll = u.p1;
    float texAspect = float(textTex.get_width()) / max(float(textTex.get_height()), 1.0);
    float bufAspect = u.resolution.x / max(u.resolution.y, 1.0);
    float vScale = 0.3 * scale;
    float2 uv;
    uv.y = (in.uv.y - 0.5) / max(vScale, 0.001) + 0.5;
    float uScale = max(vScale * texAspect / bufAspect, 0.001);
    uv.x = (in.uv.x - 0.5) / uScale + 0.5 + u.time * scroll * 0.15;
    float a = 0.0;
    if (uv.y >= 0.0 && uv.y <= 1.0) {
        a = textTex.sample(repeatSampler, uv).a;
    }
    // t=0.15 (not 0.5) and a brightness floor: several palettes dip near
    // black around the mid-point of their cosine cycle, which made text
    // read as invisible on some palette choices — a generator that varies
    // t across the frame never notices, but text needs one fixed, always
    // legible color.
    float3 color = max(palette(0.15, u.p3), float3(0.35));
    return float4(color * a, a);
}

// Layered curl-ish noise advected over time, rendered as a handful of
// bright flowing threads rather than a smooth gradient — a more "physical"
// feel than fs_gradientFlow's soft blend, closer to filaments in a fluid.
fragment float4 fs_flowField(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float density = max(u.p0 + u.modValue, 1.0);
    float speed = u.p1;
    float turb = u.p2;
    float t = u.time * speed;
    float2 p = (in.uv - 0.5) * density;
    float n1 = noise2(p + t * 0.3);
    float n2 = noise2(p * 1.7 - t * 0.2 + n1 * turb);
    float flow = noise2(p * 0.5 + float2(n2, n1) * turb + t * 0.15);
    float bands = pow(abs(sin(flow * 10.0 + t * 0.4)), 10.0);
    float3 col = palette(flow + t * 0.02, u.p3) * bands;
    return float4(col, bands);
}

// Wavy horizontal contour lines, plotter/topographic-map style — a hard
// vector-like silhouette instead of every other generator's soft shading.
fragment float4 fs_lineArt(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = in.uv - 0.5;
    float density = max(u.p0 + u.modValue, 2.0);
    float speed = u.p1;
    float wobble = u.p2;
    float t = u.time * speed;
    float wave = sin(uv.x * 6.28318 * 2.0 + t) * wobble
               + sin(uv.x * 6.28318 * 5.0 - t * 1.7) * wobble * 0.3;
    float y = uv.y + wave * 0.1;
    float lines = fract(y * density);
    float lineMask = smoothstep(0.0, 0.025, lines) - smoothstep(0.05, 0.075, lines);
    lineMask = 1.0 - lineMask;
    float3 col = palette(y * 2.0 + t * 0.05, u.p3);
    return float4(col * lineMask, lineMask);
}

// A single geometric primitive (circle/square/triangle/ring/stripes) as a
// clean, hard-edged alpha-masked shape — everything else in the catalog is
// organic/procedural shading, this is the one generator meant to be piped
// into Mask/Displace/Blend as a crisp cutout rather than shaded on its own.
fragment float4 fs_shapes(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float size = clamp(u.p0 + u.modValue * 0.6, 0.02, 1.5);
    int shapeType = int(u.p1 + 0.5);
    float softness = max(u.p2, 0.001);
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 p = in.uv - 0.5;
    p.x *= aspect;

    float d;
    if (shapeType == 0) {
        d = sdCircle(p, size * 0.4);
    } else if (shapeType == 1) {
        d = sdBox(p, float2(size * 0.35));
    } else if (shapeType == 2) {
        d = sdTriangle(p, size * 0.4);
    } else if (shapeType == 3) {
        d = abs(sdCircle(p, size * 0.4)) - size * 0.08;
    } else {
        float stripe = fract(p.x * (3.0 / max(size, 0.05)) + u.time * 0.1);
        d = abs(stripe - 0.5) - 0.25;
    }
    float mask = 1.0 - smoothstep(0.0, softness, d);
    float3 col = palette(size * 0.6 + u.time * 0.03, u.p3);
    return float4(col * mask, mask);
}

// ---------- modifiers ----------

// Ping-pong self-feed like fs_feedback, but purely an accumulating trail
// (no zoom warp) — brighter of "now" vs. a decayed memory of the last
// frame, so fast-moving highlights leave a streak behind them.
fragment float4 fs_trails(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]], texture2d<float> selfPrev [[texture(1)]]) {
    float decay = clamp(u.p0 + u.modValue * 0.15, 0.0, 0.98);
    float amount = u.p1;
    float4 cur = src.sample(modSampler, in.uv);
    float4 prev = selfPrev.sample(modSampler, in.uv) * decay;
    float4 trailed = max(cur, prev);
    return mix(cur, trailed, amount);
}

// Per-pixel luminance noise dithered over time — a cheap, always-legible
// "film" texture that reads as more expensive than it is layered on top of
// any other module.
fragment float4 fs_grain(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float amount = clamp(u.p0 + u.modValue, 0.0, 1.0);
    float size = max(u.p1, 0.5);
    float4 c = src.sample(modSampler, in.uv);
    float2 grainUV = floor(in.uv * u.resolution / size);
    float n = hash21(grainUV + fract(u.time * 60.0) * 97.0) - 0.5;
    c.rgb = saturate(c.rgb + n * amount * 0.6);
    return c;
}

// Radial channel split whose offset grows with distance from center
// (`Falloff` controls how fast) — reads as a lens/glass distortion rather
// than fs_rgbSplit's uniform directional smear.
fragment float4 fs_chromaticAberration(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float amount = clamp(u.p0 + u.modValue * 0.02, 0.0, 0.05);
    float falloff = max(u.p1, 0.1);
    float2 dir = in.uv - 0.5;
    float dist = length(dir);
    float shift = amount * pow(dist, falloff);
    float2 dirN = dist > 0.0001 ? dir / dist : float2(0.0, 0.0);
    float r = src.sample(modSampler, saturate(in.uv - dirN * shift)).r;
    float g = src.sample(modSampler, in.uv).g;
    float b = src.sample(modSampler, saturate(in.uv + dirN * shift)).b;
    float a = src.sample(modSampler, in.uv).a;
    return float4(r, g, b, a);
}

// Classic "video wall" mosaic — splits the frame into a Grid Size x Grid
// Size array of tiles, each one independently re-sampling the WHOLE
// source image (not a crop of it), with a soft dark gap between tiles.
// Turns any source (camera included) into a grid of repeated copies of
// itself.
fragment float4 fs_mosaic(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float grid = max(u.p0 + u.modValue * 8.0, 1.0);
    float gap = clamp(u.p1, 0.0, 0.3);
    float2 cell = fract(in.uv * grid);
    float4 c = src.sample(modSampler, saturate(cell));
    float edge = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
    float mask = smoothstep(0.0, gap * 0.5 + 0.001, edge);
    return float4(c.rgb * mask, c.a);
}

// Puzzle-scramble: divides the frame into a grid, and for each cell
// samples from a DIFFERENT, hash-picked cell instead of its own —
// `Seed` picks which shuffle arrangement (a new seed = a new scramble,
// not a continuous slide), `Amount` blends each cell's sampled position
// between its own square and its shuffled one, so animating Amount 0->1
// reads as the picture coming apart into its shuffled arrangement rather
// than a hard cut.
fragment float4 fs_shuffle(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float grid = max(u.p0 + u.modValue * 4.0, 1.0);
    float seed = u.p1;
    float amount = clamp(u.p2, 0.0, 1.0);
    float2 scaled = in.uv * grid;
    float2 cellID = floor(scaled);
    float2 cellUV = fract(scaled);
    float2 gridSize = float2(grid, grid);
    float2 h = hash22(cellID + seed * 97.13);
    float2 targetCell = floor(h * gridSize);
    float2 sourceCellID = mix(cellID, targetCell, amount);
    float2 uv = (sourceCellID + cellUV) / gridSize;
    return src.sample(modSampler, saturate(uv));
}

// Rigid rotation of the whole frame around its center — unlike Twirl
// (which winds harder toward the middle and barely touches the edges),
// this spins everything as one solid piece, so a shape cut out upstream
// (a Shapes ring fed through Mask, say) and whatever's showing through it
// both stay locked together and spin as a single unit. Outside the
// original square just goes transparent rather than wrapping or
// stretching.
fragment float4 fs_rotate(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float speed = u.p0 + u.modValue * 1.5;
    float angle = u.time * speed + u.p1;
    float2 center = float2(0.5, 0.5);
    float2 p = in.uv - center;
    p.x *= aspect; // square up the working buffer's real aspect first so a
                    // circular shape rotates instead of tumbling like an ellipse
    float s = sin(angle);
    float c = cos(angle);
    float2 rotated = float2(c * p.x - s * p.y, s * p.x + c * p.y);
    rotated.x /= aspect;
    rotated += center;
    if (rotated.x < 0.0 || rotated.x > 1.0 || rotated.y < 0.0 || rotated.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }
    return src.sample(modSampler, rotated);
}

// Photo-negative. `Amount` mixes between the source and its inverse
// rather than being an on/off switch, so a macro can crossfade smoothly
// into/out of the negative instead of only hard-cutting.
fragment float4 fs_invert(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float amount = clamp(u.p0 + u.modValue, 0.0, 1.0);
    float4 c = src.sample(modSampler, in.uv);
    float3 inverted = 1.0 - c.rgb;
    return float4(mix(c.rgb, inverted, amount), c.a);
}

// Rhythmic flash — `Rate` pulses per second, `Duty` how much of each
// cycle is "on" (short Duty = a sharp strobe hit, long Duty = more of a
// slow pulse), `Color` picks whether it flashes toward white (1, the
// classic rave strobe) or toward black (0, a blackout flicker instead).
// `Amount` scales how much of the flash actually shows through, so a
// macro can ride it from "no strobe" up to "full white-out" continuously.
fragment float4 fs_strobe(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float rate = max(u.p0 + u.modValue * 8.0, 0.1);
    float amount = clamp(u.p1, 0.0, 1.0);
    float duty = clamp(u.p2, 0.05, 0.95);
    float colorMix = clamp(u.p3, 0.0, 1.0);
    float4 c = src.sample(modSampler, in.uv);
    float phase = fract(u.time * rate);
    float pulse = phase < duty ? 1.0 : 0.0;
    // A hard threshold, not `mix` — `colorMix` is driven by a macro in
    // every template/scene, and a macro sitting anywhere near its 0.5
    // default (or drifting slowly through it, as the Auto Director's
    // rider does) would otherwise flash a washed-out GRAY instead of a
    // crisp black or white strobe. `step` makes every value except
    // exactly 0.5 commit fully to one or the other.
    float3 flashColor = float3(step(0.5, colorMix));
    float3 result = mix(c.rgb, flashColor, pulse * amount);
    return float4(result, c.a);
}

// VHS tape look: horizontal "tracking" bands that roll downward and
// shove a strip of the image sideways (the classic mistracked-tape
// glitch), RGB color-bleed (each channel sampled from a slightly
// different X), and per-line static/interference noise.
fragment float4 fs_vhs(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float tracking = clamp(u.p0 + u.modValue, 0.0, 1.0);
    float noiseAmt = clamp(u.p1, 0.0, 1.0);
    float bleed = clamp(u.p2, 0.0, 1.0);
    float speed = max(u.p3, 0.0);

    float2 uv = in.uv;

    // A handful of horizontal bands per roll cycle randomly "activate"
    // and shove that strip of the image sideways — rolling slowly down
    // the frame over time like a tape struggling to hold tracking.
    float rollY = fract(uv.y - u.time * speed * 0.08);
    float bandNoise = hash21(float2(floor(rollY * 24.0), floor(u.time * 2.0)));
    float bandActive = step(0.85, bandNoise) * tracking;
    uv.x += (bandNoise - 0.5) * 0.06 * bandActive;

    float bleedAmt = bleed * 0.01;
    float r = src.sample(modSampler, saturate(float2(uv.x - bleedAmt, uv.y))).r;
    float g = src.sample(modSampler, saturate(uv)).g;
    float b = src.sample(modSampler, saturate(float2(uv.x + bleedAmt, uv.y))).b;
    float a = src.sample(modSampler, saturate(uv)).a;

    float staticNoise = (hash21(float2(floor(uv.y * u.resolution.y), floor(u.time * 30.0))) - 0.5) * noiseAmt * 0.35;

    return float4(saturate(float3(r, g, b) + staticNoise), a);
}

// Old damaged film reel: stepped brightness flicker (frame-rate-ish, not
// smooth), a few thin bright vertical scratches drifting slowly, and a
// sepia tone mixed in over the source color.
fragment float4 fs_oldFilm(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float flicker = clamp(u.p0 + u.modValue, 0.0, 1.0);
    float scratchAmt = clamp(u.p1, 0.0, 1.0);
    float sepia = clamp(u.p2, 0.0, 1.0);
    float speed = max(u.p3, 0.0);

    float4 c = src.sample(modSampler, in.uv);

    float flickerPhase = floor(u.time * (8.0 + speed * 10.0));
    float flickerNoise = hash21(float2(flickerPhase, 1.7));
    float brightness = 1.0 - flicker * flickerNoise * 0.35;

    float scratches = 0.0;
    for (int i = 0; i < 3; i++) {
        float seed = float(i) * 13.7 + floor(u.time * (0.4 + speed * 0.6));
        float lineX = hash21(float2(seed, 0.0));
        scratches += smoothstep(0.0015, 0.0, abs(in.uv.x - lineX));
    }
    scratches = saturate(scratches) * scratchAmt;

    float3 sepiaColor = float3(dot(c.rgb, float3(0.393, 0.769, 0.189)),
                                dot(c.rgb, float3(0.349, 0.686, 0.168)),
                                dot(c.rgb, float3(0.272, 0.534, 0.131)));
    float3 toned = mix(c.rgb, sepiaColor, sepia);
    float3 result = toned * brightness + scratches * 0.6;
    return float4(saturate(result), c.a);
}

// A glowing dot that hunts for edges/lines in the source image and rides
// along them — self-feeding like Feedback/Reaction (texture(1) is this
// node's OWN previous output, bound by RenderEngine), but here that
// self-read isn't a visual trail, it's memory: one fixed pixel (the very
// first texel) is repurposed to persist the orb's (x, y, heading) from
// frame to frame instead of showing image content, and every other pixel
// re-derives the same position/heading from that same texel each frame
// (redundant per-pixel work, but cheap, and avoids needing any CPU-side
// state at all — the whole simulation lives on the GPU).
//
// Each frame: sample a Sobel gradient of source luminance AROUND the
// orb's current position (same gradient math as Edge Detect), rotate it
// 90 degrees to get the direction that runs ALONG the edge rather than
// across it, and steer the orb's heading toward that tangent whenever a
// real edge is nearby — otherwise it wanders gently instead of freezing
// in a flat region. Bounces off frame edges rather than wrapping (a wrap
// would teleport the glow, which reads as a glitch, not a bounce).
fragment float4 fs_lightOrb(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]], texture2d<float> selfPrev [[texture(1)]]) {
    float speed = max(u.p0 + u.modValue * 2.0, 0.0);
    float sensitivity = clamp(u.p1, 0.0, 1.0);
    float glowSize = clamp(u.p2, 0.01, 0.2);

    float2 texel = 1.0 / max(u.resolution, float2(1.0));
    float2 storageUV = texel * 0.5;

    float4 state = selfPrev.sample(modSampler, storageUV);
    float2 pos = state.rg;
    float velAngle = state.b * 6.28318;
    if (pos.x <= 0.0001 && pos.y <= 0.0001) { pos = float2(0.5, 0.5); velAngle = 1.3; }

    float3 lum3 = float3(0.299, 0.587, 0.114);
    float lTL = dot(src.sample(modSampler, saturate(pos + texel * float2(-1, -1))).rgb, lum3);
    float lTR = dot(src.sample(modSampler, saturate(pos + texel * float2(1, -1))).rgb, lum3);
    float lBL = dot(src.sample(modSampler, saturate(pos + texel * float2(-1, 1))).rgb, lum3);
    float lBR = dot(src.sample(modSampler, saturate(pos + texel * float2(1, 1))).rgb, lum3);
    float lL = dot(src.sample(modSampler, saturate(pos + texel * float2(-1, 0))).rgb, lum3);
    float lR = dot(src.sample(modSampler, saturate(pos + texel * float2(1, 0))).rgb, lum3);
    float lT = dot(src.sample(modSampler, saturate(pos + texel * float2(0, -1))).rgb, lum3);
    float lB = dot(src.sample(modSampler, saturate(pos + texel * float2(0, 1))).rgb, lum3);
    float gx = -lTL - 2.0 * lL - lBL + lTR + 2.0 * lR + lBR;
    float gy = -lTL - 2.0 * lT - lTR + lBL + 2.0 * lB + lBR;
    float edgeStrength = length(float2(gx, gy));

    float2 edgeTangent = normalize(float2(-gy, gx) + 1e-5);
    float edgeAngle = atan2(edgeTangent.y, edgeTangent.x);

    float follow = smoothstep(0.05, 0.05 + (1.0 - sensitivity) * 0.4, edgeStrength);
    float wander = (hash21(pos * 97.0 + u.time * 0.7) - 0.5) * 0.6;
    float targetAngle = mix(velAngle + wander, edgeAngle, follow);

    // A tangent line has no inherent "forward" — if the nearest tangent
    // direction points backward relative to current heading, flip it so
    // the orb keeps moving forward along the edge instead of reversing.
    float diff = targetAngle - velAngle;
    diff -= 6.28318 * floor((diff + 3.14159) / 6.28318);
    if (abs(diff) > 3.14159 * 0.5 && follow > 0.5) {
        targetAngle += 3.14159;
        diff = targetAngle - velAngle;
        diff -= 6.28318 * floor((diff + 3.14159) / 6.28318);
    }
    float newAngle = velAngle + diff * 0.15;

    float2 newPos = pos + float2(cos(newAngle), sin(newAngle)) * speed * 0.0025;
    if (newPos.x < 0.0 || newPos.x > 1.0) { newAngle = 3.14159265 - newAngle; }
    if (newPos.y < 0.0 || newPos.y > 1.0) { newAngle = -newAngle; }
    newPos = clamp(newPos, 0.0, 1.0);

    if (in.uv.x < texel.x && in.uv.y < texel.y) {
        return float4(newPos.x, newPos.y, fract(newAngle / 6.28318), 1.0);
    }

    float4 c = src.sample(modSampler, in.uv);
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 d = in.uv - newPos;
    d.x *= aspect;
    float dist = length(d);
    // Size "breathes" over time (own hashed phase per orb path so it never
    // looks synced to anything else on screen) and swells a bit on strong
    // edges, so the orb feels alive instead of a fixed-radius dot.
    float pulse = 0.75 + 0.25 * sin(u.time * 1.3 + hash21(pos * 13.0) * 6.28318);
    float animatedSize = glowSize * pulse * mix(1.0, 1.3, saturate(edgeStrength * 2.0));
    float glow = exp(-dist * dist / max(animatedSize * animatedSize, 0.0001));
    float3 orbColor = palette(0.2, u.p3);
    return float4(saturate(c.rgb + orbColor * glow * 1.4), c.a);
}

// Spotlight — same edge-following orb logic as fs_lightOrb, but instead of
// adding a glowing dot on top of the full image, it MASKS the image: the
// frame is black everywhere except inside the beam, where the real source
// image "shows through" (a follow-spot / stage-light simulator). Reuses the
// identical self-feedback position state so both modules could even share a
// texel format, but each keeps its own feedback texture per node instance.
fragment float4 fs_spotlight(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]], texture2d<float> selfPrev [[texture(1)]]) {
    float speed = max(u.p0 + u.modValue * 2.0, 0.0);
    float sensitivity = clamp(u.p1, 0.0, 1.0);
    float beamSize = clamp(u.p2, 0.01, 0.3);
    float softness = clamp(u.p3, 0.2, 3.0);

    float2 texel = 1.0 / max(u.resolution, float2(1.0));
    float2 storageUV = texel * 0.5;

    float4 state = selfPrev.sample(modSampler, storageUV);
    float2 pos = state.rg;
    float velAngle = state.b * 6.28318;
    if (pos.x <= 0.0001 && pos.y <= 0.0001) { pos = float2(0.5, 0.5); velAngle = 1.3; }

    float3 lum3 = float3(0.299, 0.587, 0.114);
    float lTL = dot(src.sample(modSampler, saturate(pos + texel * float2(-1, -1))).rgb, lum3);
    float lTR = dot(src.sample(modSampler, saturate(pos + texel * float2(1, -1))).rgb, lum3);
    float lBL = dot(src.sample(modSampler, saturate(pos + texel * float2(-1, 1))).rgb, lum3);
    float lBR = dot(src.sample(modSampler, saturate(pos + texel * float2(1, 1))).rgb, lum3);
    float lL = dot(src.sample(modSampler, saturate(pos + texel * float2(-1, 0))).rgb, lum3);
    float lR = dot(src.sample(modSampler, saturate(pos + texel * float2(1, 0))).rgb, lum3);
    float lT = dot(src.sample(modSampler, saturate(pos + texel * float2(0, -1))).rgb, lum3);
    float lB = dot(src.sample(modSampler, saturate(pos + texel * float2(0, 1))).rgb, lum3);
    float gx = -lTL - 2.0 * lL - lBL + lTR + 2.0 * lR + lBR;
    float gy = -lTL - 2.0 * lT - lTR + lBL + 2.0 * lB + lBR;
    float edgeStrength = length(float2(gx, gy));

    float2 edgeTangent = normalize(float2(-gy, gx) + 1e-5);
    float edgeAngle = atan2(edgeTangent.y, edgeTangent.x);

    float follow = smoothstep(0.05, 0.05 + (1.0 - sensitivity) * 0.4, edgeStrength);
    float wander = (hash21(pos * 97.0 + u.time * 0.7) - 0.5) * 0.6;
    float targetAngle = mix(velAngle + wander, edgeAngle, follow);

    float diff = targetAngle - velAngle;
    diff -= 6.28318 * floor((diff + 3.14159) / 6.28318);
    if (abs(diff) > 3.14159 * 0.5 && follow > 0.5) {
        targetAngle += 3.14159;
        diff = targetAngle - velAngle;
        diff -= 6.28318 * floor((diff + 3.14159) / 6.28318);
    }
    float newAngle = velAngle + diff * 0.15;

    float2 newPos = pos + float2(cos(newAngle), sin(newAngle)) * speed * 0.0025;
    if (newPos.x < 0.0 || newPos.x > 1.0) { newAngle = 3.14159265 - newAngle; }
    if (newPos.y < 0.0 || newPos.y > 1.0) { newAngle = -newAngle; }
    newPos = clamp(newPos, 0.0, 1.0);

    if (in.uv.x < texel.x && in.uv.y < texel.y) {
        return float4(newPos.x, newPos.y, fract(newAngle / 6.28318), 1.0);
    }

    float4 c = src.sample(modSampler, in.uv);
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 d = in.uv - newPos;
    d.x *= aspect;
    float dist = length(d);
    // Two waves at different speeds, own hashed phase per path so several
    // spotlight nodes never sync up: a slow one drives big, occasional
    // swells (cubed so it spends most of its time small and only spikes
    // wide a few times per minute) and a fast one adds a light flicker on
    // top. Without the slow swell the beam reads as a fixed-size dot that
    // just happens to move — this is what makes it periodically flood open
    // and actually "illuminate" a wide patch of the image before shrinking
    // back down to a tight spot.
    float slowPhase = u.time * 0.09 + hash21(pos * 13.0) * 6.28318;
    float slow = 0.5 + 0.5 * sin(slowPhase);
    float swell = pow(slow, 3.0);
    float flicker = 0.9 + 0.1 * sin(u.time * 2.2 + hash21(pos * 31.0) * 6.28318);
    float animatedSize = beamSize * mix(0.6, 5.0, swell) * flicker * mix(1.0, 1.3, saturate(edgeStrength * 2.0));
    // `softness` shapes the falloff exponent — low values give a sharp
    // theatrical spot edge, high values give a soft diffuse glow of reveal.
    float falloff = pow(saturate(dist / max(animatedSize, 0.0001)), softness);
    float beam = saturate(1.0 - falloff);
    return float4(c.rgb * beam, c.a * beam);
}

// Crops a square (undistorted regardless of the frame's own aspect ratio)
// region of `src` centered on `face` (xy = center, zw = half-size, all
// normalized 0...1), remapping `destUV` (0...1 within that crop, or within
// one grid cell of it) into source UV. Shared by fs_faceZoom and
// fs_faceGrid — both are otherwise just different arrangements of the same
// crop math.
float2 faceCropUV(float4 face, float2 destUV, float padding, float2 resolution) {
    float halfPx = max(face.z * resolution.x, face.w * resolution.y) * padding;
    float2 halfUV = float2(halfPx / max(resolution.x, 1.0), halfPx / max(resolution.y, 1.0));
    return face.xy + (destUV - 0.5) * 2.0 * halfUV;
}

// "Face Close-Up" — punches into whatever face `CameraCaptureEngine`
// currently tracks as largest (`u.face0`, already smoothed/held on the CPU
// side against detector jitter and brief dropouts). With nobody in frame,
// holds a gentle center zoom instead of an abrupt cut back to the full wide
// shot — `AutoDirectorEngine`/a manual patch is expected to only route INTO
// this modifier some of the time, not replace the camera outright.
fragment float4 fs_faceZoom(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float padding = clamp(u.p0 + u.modValue, 1.0, 4.0);
    float verticalBias = clamp(u.p1, -0.3, 0.3);
    float fallbackZoom = clamp(u.p2, 1.0, 3.0);

    float2 uv;
    if (u.faceCount > 0.5) {
        float2 biased = u.face0.xy + float2(0.0, verticalBias * u.face0.w);
        float4 face = float4(biased, u.face0.zw);
        uv = faceCropUV(face, in.uv, padding, u.resolution);
    } else {
        uv = 0.5 + (in.uv - 0.5) / fallbackZoom;
    }
    return src.sample(modSampler, saturate(uv));
}

// "Face Grid" — a video-call-style tile of every tracked face (1 = a single
// full-frame close-up identical to fs_faceZoom, 2 = left/right split,
// 3 = one tall cell + two stacked), each cell independently cropped via the
// same `faceCropUV`. No faces tracked: passes the source through untouched
// rather than showing an empty grid.
fragment float4 fs_faceGrid(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float padding = clamp(u.p0 + u.modValue, 1.0, 4.0);
    float gap = clamp(u.p1, 0.0, 0.06);
    int count = int(clamp(u.faceCount, 0.0, 3.0));
    float cellExtent = 0.5 - gap * 0.5;

    if (count <= 0) {
        return src.sample(modSampler, in.uv);
    }
    if (count == 1) {
        return src.sample(modSampler, saturate(faceCropUV(u.face0, in.uv, padding, u.resolution)));
    }
    if (in.uv.x < 0.5 - gap * 0.5) {
        float2 cellUV = float2(in.uv.x / cellExtent, in.uv.y);
        return src.sample(modSampler, saturate(faceCropUV(u.face0, cellUV, padding, u.resolution)));
    }
    if (in.uv.x <= 0.5 + gap * 0.5) {
        return float4(0.0, 0.0, 0.0, 1.0); // vertical divider
    }
    float rightX = (in.uv.x - (0.5 + gap * 0.5)) / cellExtent;
    if (count == 2) {
        return src.sample(modSampler, saturate(faceCropUV(u.face1, float2(rightX, in.uv.y), padding, u.resolution)));
    }
    // count == 3: right column split top/bottom between face1 and face2.
    if (in.uv.y < 0.5 - gap * 0.5) {
        float2 cellUV = float2(rightX, in.uv.y / cellExtent);
        return src.sample(modSampler, saturate(faceCropUV(u.face1, cellUV, padding, u.resolution)));
    }
    if (in.uv.y <= 0.5 + gap * 0.5) {
        return float4(0.0, 0.0, 0.0, 1.0); // horizontal divider
    }
    float2 cellUV = float2(rightX, (in.uv.y - (0.5 + gap * 0.5)) / cellExtent);
    return src.sample(modSampler, saturate(faceCropUV(u.face2, cellUV, padding, u.resolution)));
}

// "Face Spotlight" — the spotlight/reveal idea (fs_spotlight) combined with
// real face tracking instead of edge-following: the beam eases toward
// `u.face0` (the largest tracked face) every frame, self-feeding its own
// smoothed position the same way fs_spotlight/fs_lightOrb do. With no face
// tracked, it holds its last position rather than snapping back to center
// or resuming an edge search — a face reappearing is what should move it,
// not the absence of one.
fragment float4 fs_faceSpotlight(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]], texture2d<float> selfPrev [[texture(1)]]) {
    float speed = clamp(u.p0 + u.modValue, 0.05, 1.0);
    float beamSize = clamp(u.p1, 0.01, 0.3);
    float softness = clamp(u.p2, 0.2, 3.0);

    float2 texel = 1.0 / max(u.resolution, float2(1.0));
    float2 storageUV = texel * 0.5;
    float4 state = selfPrev.sample(modSampler, storageUV);
    float2 pos = state.xy;
    if (pos.x <= 0.0001 && pos.y <= 0.0001) { pos = float2(0.5, 0.5); }

    float2 target = (u.faceCount > 0.5) ? u.face0.xy : pos;
    float2 newPos = mix(pos, target, speed);

    if (in.uv.x < texel.x && in.uv.y < texel.y) {
        return float4(newPos.x, newPos.y, 0.0, 1.0);
    }

    float4 c = src.sample(modSampler, in.uv);
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 d = in.uv - newPos;
    d.x *= aspect;
    float dist = length(d);
    // Leans toward the tracked face's own half-size (so the beam roughly
    // matches how close the face actually is) while still letting Beam
    // Size have real influence, rather than one fully overriding the other.
    float faceHalf = (u.faceCount > 0.5) ? max(u.face0.z, u.face0.w) : beamSize;
    float animatedSize = mix(beamSize, faceHalf * 1.6, 0.6);
    float falloff = pow(saturate(dist / max(animatedSize, 0.0001)), softness);
    float beam = saturate(1.0 - falloff);
    return float4(c.rgb * beam, c.a * beam);
}

// ---------- modifiers (existing) ----------

// 9x9 separable-weight Gaussian (applied as a single pass over both axes —
// v1 favors one texture read over two passes for simplicity). `Amount`
// (0...1, modulatable) sets the blur radius in texels; `Quality` widens the
// step between taps so a big radius doesn't need more samples, at some cost
// in ring artifacts at the largest sizes.
fragment float4 fs_blur(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float amount = saturate(u.p0 + u.modValue * 0.5);
    float texel = 1.0 / max(u.resolution.x, 1.0);
    float step = texel * mix(1.0, 3.0, saturate((u.p1 - 1.0) * 0.5));
    float radius = amount * 18.0;
    float4 sum = float4(0.0);
    float total = 0.0;
    for (int x = -4; x <= 4; x++) {
        for (int y = -4; y <= 4; y++) {
            float2 tap = float2(float(x), float(y));
            float w = exp(-dot(tap, tap) * 0.18);
            float2 offset = tap * step * radius;
            sum += src.sample(modSampler, in.uv + offset) * w;
            total += w;
        }
    }
    return sum / max(total, 0.0001);
}

fragment float4 fs_hueRotate(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float4 c = src.sample(modSampler, in.uv);
    float rot = fract(u.p0 + u.modValue) * 6.28318;
    float3x3 m = rotZ(rot);
    float3 yiq = float3(dot(c.rgb, float3(0.299, 0.587, 0.114)),
                         dot(c.rgb, float3(0.596, -0.274, -0.322)),
                         dot(c.rgb, float3(0.211, -0.523, 0.312)));
    float3 rotated = m * float3(0, yiq.y, yiq.z);
    float3 out = float3(yiq.x + rotated.y, yiq.x - 0.272 * rotated.y - 0.647 * rotated.z, yiq.x - 1.106 * rotated.y + 1.703 * rotated.z);
    out = mix(float3(dot(out, float3(0.333))), out, u.p1);
    return float4(saturate(out), c.a);
}

// Reflects everything on the far side of an axis line back onto the near
// side. `Offset` (-1...1) slides that axis line itself across the frame —
// previously it only nudged the compare threshold, which barely moved the
// visible seam; folding around `axis + offset*0.5` actually relocates it.
fragment float4 fs_mirror(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float2 uv = in.uv;
    int axis = int(round(u.p0 + u.modValue * 2.0)) % 3;
    float axisX = 0.5 + u.p1 * 0.5;
    float axisY = 0.5 + u.p1 * 0.5;
    if (axis == 0) uv.x = axisX - abs(uv.x - axisX);
    else if (axis == 1) uv.y = axisY - abs(uv.y - axisY);
    else {
        uv.x = axisX - abs(uv.x - axisX);
        uv.y = axisY - abs(uv.y - axisY);
    }
    return src.sample(modSampler, saturate(uv));
}

fragment float4 fs_rgbSplit(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float amount = u.p0 + u.modValue * 0.05;
    float2 dir = float2(cos(u.p1), sin(u.p1));
    float r = src.sample(modSampler, in.uv + dir * amount).r;
    float g = src.sample(modSampler, in.uv).g;
    float b = src.sample(modSampler, in.uv - dir * amount).b;
    float a = src.sample(modSampler, in.uv).a;
    return float4(r, g, b, a);
}

fragment float4 fs_pixelate(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float cell = max(1.0, u.p0 + u.modValue * 40.0);
    float2 res = u.resolution;
    float2 uv = floor(in.uv * res / cell) * cell / res;
    return src.sample(modSampler, uv);
}

fragment float4 fs_bloom(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float4 c = src.sample(modSampler, in.uv);
    float threshold = u.p0;
    float intensity = u.p1 + u.modValue * 2.0;
    float4 bloomSum = float4(0.0);
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            float2 offset = float2(float(x), float(y)) * 3.0 / max(u.resolution.x, 1.0);
            float4 s = src.sample(modSampler, in.uv + offset);
            float lum = dot(s.rgb, float3(0.299, 0.587, 0.114));
            bloomSum += s * step(threshold, lum);
        }
    }
    bloomSum /= 25.0;
    return float4(tonemap(c.rgb + bloomSum.rgb * intensity), c.a);
}

fragment float4 fs_scanlines(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float4 c = src.sample(modSampler, in.uv);
    float density = u.p0 + u.modValue * 400.0;
    float intensity = u.p1;
    float line = sin(in.uv.y * density) * 0.5 + 0.5;
    c.rgb *= mix(1.0, line, intensity);
    return c;
}

// texture(0) is this frame's live chain input; texture(1) is this same
// feedback node's own output from the previous frame (fed back in by
// RenderEngine from the ping-pong buffer's read side), which is what makes
// the trail actually accumulate across frames instead of resetting.
fragment float4 fs_feedback(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]], texture2d<float> selfPrev [[texture(1)]]) {
    float decay = saturate(u.p0 + u.modValue * 0.15);
    float zoom = u.p1;
    float2 center = float2(0.5, 0.5);
    float2 uv = (in.uv - center) * zoom + center;
    float4 prev = selfPrev.sample(modSampler, uv);
    float4 cur = src.sample(modSampler, in.uv);
    return mix(cur, prev, decay);
}

// Rotates pixels around center by an angle that falls off with distance
// (Gaussian falloff), so the middle spins hardest and the edges barely move.
fragment float4 fs_twirl(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 center = float2(0.5, 0.5);
    float2 uv = in.uv - center;
    uv.x *= aspect;
    float radius = max(0.05, u.p1);
    float strength = u.p0 + u.modValue * 4.0;
    float d = length(uv) / radius;
    float angle = strength * exp(-d * d);
    float s = sin(angle), c = cos(angle);
    float2 rotated = float2(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
    rotated.x /= aspect;
    return src.sample(modSampler, rotated + center);
}

// Block-glitch: on a per-block, per-tenth-of-a-second hash roll, jitters
// that block's sample position and occasionally tears its red channel —
// distinct from RGB Split (a constant global offset) in that it's
// localized, intermittent, and blocky rather than a smooth uniform shift.
fragment float4 fs_datamosh(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float amount = saturate(u.p0 + u.modValue * 0.6);
    float blockSize = max(2.0, u.p1);
    float2 block = floor(in.uv * u.resolution / blockSize);
    float tick = floor(u.time * 6.0);
    float r = hash21(block + tick);
    float2 offset = float2(0.0);
    if (r < amount) {
        offset = (hash22(block + tick * 3.1) - 0.5) * 0.08;
    }
    float2 uv = in.uv + offset;
    float4 c = src.sample(modSampler, uv);
    if (r < amount * 0.4) {
        c.r = src.sample(modSampler, uv + float2(0.01, 0.0)).r;
    }
    return c;
}

fragment float4 fs_posterize(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float4 c = src.sample(modSampler, in.uv);
    float levels = max(2.0, u.p0 + u.modValue * 14.0);
    float gamma = max(0.2, u.p1);
    float3 g = pow(saturate(c.rgb), float3(gamma));
    float3 posterized = floor(g * levels) / (levels - 1.0);
    return float4(saturate(posterized), c.a);
}

// Sobel edge magnitude; `Mix` blends between the plain edge map (1.0) and
// the untouched source (0.0) so it can either replace the image entirely or
// just sketch a faint outline over it.
fragment float4 fs_edgeDetect(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float2 texel = 1.0 / max(u.resolution, float2(1.0));
    float3 tl = src.sample(modSampler, in.uv + texel * float2(-1, -1)).rgb;
    float3 tr = src.sample(modSampler, in.uv + texel * float2(1, -1)).rgb;
    float3 bl = src.sample(modSampler, in.uv + texel * float2(-1, 1)).rgb;
    float3 br = src.sample(modSampler, in.uv + texel * float2(1, 1)).rgb;
    float3 l = src.sample(modSampler, in.uv + texel * float2(-1, 0)).rgb;
    float3 r = src.sample(modSampler, in.uv + texel * float2(1, 0)).rgb;
    float3 t = src.sample(modSampler, in.uv + texel * float2(0, -1)).rgb;
    float3 b = src.sample(modSampler, in.uv + texel * float2(0, 1)).rgb;
    float3 gx = -tl - 2.0 * l - bl + tr + 2.0 * r + br;
    float3 gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
    float edge = length(gx) + length(gy);
    float threshold = u.p0 + u.modValue * 0.5;
    float e = smoothstep(threshold, threshold + 0.4, edge);
    float4 original = src.sample(modSampler, in.uv);
    return float4(mix(original.rgb, float3(e), saturate(u.p1)), original.a);
}

fragment float4 fs_vignette(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float4 c = src.sample(modSampler, in.uv);
    float amount = saturate(u.p0 + u.modValue * 0.8);
    float2 d = in.uv - 0.5;
    float vig = 1.0 - amount * dot(d, d) * 2.2;
    float grain = (hash21(in.uv * u.resolution + u.time * 60.0) - 0.5) * saturate(u.p1) * 0.25;
    c.rgb = saturate(c.rgb * vig + grain);
    return c;
}

// Fixed-key (green-screen) chroma key — v1 doesn't have a color-parameter
// UI yet, so the key color is pinned to pure green rather than
// user-pickable. Keyed-out pixels go to black and carry a 0 alpha, so a
// downstream Mask/Blend/Displace combiner can composite them properly, or
// it reads fine on its own as an instant cutout.
fragment float4 fs_chromaKey(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float4 c = src.sample(modSampler, in.uv);
    float3 key = float3(0.0, 1.0, 0.0);
    float dist = distance(normalize(c.rgb + 0.0001), key);
    float threshold = u.p0 + u.modValue * 0.6;
    float softness = max(0.001, u.p1);
    float mask = smoothstep(threshold, threshold + softness, dist);
    return float4(c.rgb * mask, mask);
}

// ---------- combiners ----------

fragment float4 fs_blend(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> a [[texture(0)]], texture2d<float> b [[texture(1)]]) {
    float4 ca = a.sample(modSampler, in.uv);
    float4 cb = b.sample(modSampler, in.uv);
    int mode = int(u.p1);
    float mixAmount = saturate(u.p0);
    float3 result;
    if (mode == 0) result = ca.rgb + cb.rgb * mixAmount;
    else if (mode == 1) result = 1.0 - (1.0 - ca.rgb) * (1.0 - cb.rgb * mixAmount);
    else if (mode == 2) result = ca.rgb * mix(float3(1.0), cb.rgb, mixAmount);
    else result = mix(ca.rgb, cb.rgb, mixAmount);
    return float4(saturate(result), max(ca.a, cb.a));
}

fragment float4 fs_mask(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> a [[texture(0)]], texture2d<float> b [[texture(1)]]) {
    float4 ca = a.sample(modSampler, in.uv);
    float4 cb = b.sample(modSampler, in.uv);
    float lum = dot(cb.rgb, float3(0.299, 0.587, 0.114));
    float mask = step(u.p0, lum);
    return float4(ca.rgb * mask, ca.a);
}

fragment float4 fs_difference(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> a [[texture(0)]], texture2d<float> b [[texture(1)]]) {
    float4 ca = a.sample(modSampler, in.uv);
    float4 cb = b.sample(modSampler, in.uv);
    float3 diff = abs(ca.rgb - cb.rgb) * u.p0;
    return float4(diff, max(ca.a, cb.a));
}

// B's red/green channels push A's sample position around — a cheap
// "liquid" distortion where one branch's brightness pattern warps the
// other's shape, rather than a flat compositing blend.
fragment float4 fs_displace(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> a [[texture(0)]], texture2d<float> b [[texture(1)]]) {
    float4 cb = b.sample(modSampler, in.uv);
    float amount = u.p0 * 0.15;
    float scale = max(0.1, u.p1);
    float2 offset = (cb.rg - 0.5) * amount * scale;
    float4 ca = a.sample(modSampler, in.uv + offset);
    return float4(ca.rgb, max(ca.a, cb.a));
}

fragment float4 fs_lumaKey(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> a [[texture(0)]], texture2d<float> b [[texture(1)]]) {
    float4 ca = a.sample(modSampler, in.uv);
    float4 cb = b.sample(modSampler, in.uv);
    float lumB = dot(cb.rgb, float3(0.299, 0.587, 0.114));
    float threshold = u.p0;
    float softness = max(0.001, u.p1);
    float mask = smoothstep(threshold, threshold + softness, lumB);
    return float4(mix(ca.rgb, cb.rgb, mask), max(ca.a, cb.a));
}

// Crossfades A->B automatically as u.beatStrength rises through
// Threshold...Threshold+Softness — a hands-free transition for a live set
// instead of a Blend node's manually-dialed Mix.
fragment float4 fs_beatCrossfade(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> a [[texture(0)]], texture2d<float> b [[texture(1)]]) {
    float4 ca = a.sample(modSampler, in.uv);
    float4 cb = b.sample(modSampler, in.uv);
    float threshold = u.p0;
    float softness = max(0.001, u.p1);
    float amount = smoothstep(threshold, threshold + softness, u.beatStrength);
    return float4(mix(ca.rgb, cb.rgb, amount), max(ca.a, cb.a));
}

// Mirrors A's sampling angle into a repeating pie-slice wedge (same trick
// as fs_kaleido, applied to an existing texture instead of a raw pattern)
// before mixing with B — much busier, more "kaleidoscope projector" look
// than a plain blend.
fragment float4 fs_kaleidoMix(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> a [[texture(0)]], texture2d<float> b [[texture(1)]]) {
    float segments = max(u.p0 + u.modValue * 8.0, 2.0);
    float mixAmount = u.p1;
    float2 center = in.uv - 0.5;
    float radius = length(center);
    float angle = atan2(center.y, center.x);
    float seg = 6.28318 / segments;
    angle = fmod(angle, seg);
    if (angle < 0.0) { angle += seg; }
    angle = abs(angle - seg * 0.5);
    float2 kUV = float2(cos(angle), sin(angle)) * radius + 0.5;
    float4 ca = a.sample(modSampler, saturate(kUV));
    float4 cb = b.sample(modSampler, in.uv);
    return mix(ca, cb, mixAmount);
}

// Directional hard-edge (softened) transition line sweeping across the
// frame — the classic VJ "wipe" cut between two sources, driven by
// `Position` (0 = all A, 1 = all B) so it can ride a macro/LFO for a
// rhythmic transition instead of a one-shot cut.
fragment float4 fs_wipe(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> a [[texture(0)]], texture2d<float> b [[texture(1)]]) {
    float pos = clamp(u.p0 + u.modValue, 0.0, 1.0);
    float angle = u.p1;
    float softness = max(u.p2, 0.001);
    float2 dir = float2(cos(angle), sin(angle));
    float proj = dot(in.uv - 0.5, dir) + 0.5;
    float t = smoothstep(pos - softness, pos + softness, proj);
    float4 ca = a.sample(modSampler, in.uv);
    float4 cb = b.sample(modSampler, in.uv);
    return mix(ca, cb, t);
}

// ---------- present ----------

// `coverScale` (set by RenderEngine each frame from workingSize vs. the
// live drawable size) maps screen UV to a centered, aspect-correct crop of
// the source texture — "cover" fit, like CSS background-size:cover — so a
// 16:9 working buffer fills a tall fullscreen portrait view by cropping the
// sides instead of squeezing the whole image into that shape.
struct PresentUniforms {
    float2 coverScale;
};

fragment float4 fs_present(VertexOut in [[stage_in]], constant PresentUniforms &pu [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float2 uv = (in.uv - 0.5) * pu.coverScale + 0.5;
    return src.sample(modSampler, saturate(uv));
}

// Fallback: flat dim color for an unpatched / not-yet-implemented node so a
// broken chain reads as "off" rather than crashing the render plan.
fragment float4 fs_blank(VertexOut in [[stage_in]]) {
    return float4(0.03, 0.03, 0.04, 1.0);
}
