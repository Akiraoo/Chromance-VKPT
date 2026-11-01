#ifndef CHR_WAVES_GLSL
#define CHR_WAVES_GLSL

// Gentle water waves: a few long, smooth wave trains in different directions, slowly drifting. Only low
// frequencies, so they never break up into the moire or "mosaic glass" look. Shared by the post-process wave
// overlay (post/water_waves.frag) and the underwater caustics. p: absolute world XZ, t: seconds.

vec3 chrWaveTrain(vec2 p, float t, vec2 dir, float wavelength, float speed, float amplitude) {
    float k = 6.2831853 / wavelength;
    float phase = dot(p, dir) * k + t * speed * k;
    // returns height, d/dx, d/dz
    return vec3(sin(phase) * amplitude, dir * cos(phase) * amplitude * k);
}

// Each wave train is faded out once one screen pixel covers a sizeable part of its wavelength, so distant or
// grazing water does not turn into a pattern of scales. footprint: size of a pixel on the water, in blocks
// (0 = no filtering).
float chrWaveLod(float wavelength, float footprint) {
    return 1.0 - smoothstep(0.08, 0.30, footprint / wavelength);
}

float chrWvHash(vec2 i) {
    uvec2 q = uvec2(ivec2(i));
    uint h = q.x * 0x8da6b343u ^ q.y * 0xd8163841u;
    h ^= h >> 16u;
    h *= 0x7feb352du;
    h ^= h >> 15u;
    h *= 0x846ca68bu;
    h ^= h >> 16u;
    return float(h) * (1.0 / 4294967295.0);
}

// Smooth value noise in -1..1 with its derivative: .x = value, .yz = d/dx, d/dz.
vec3 chrWvNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = p - i;
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
    float a = chrWvHash(i);
    float b = chrWvHash(i + vec2(1.0, 0.0));
    float c = chrWvHash(i + vec2(0.0, 1.0));
    float d = chrWvHash(i + vec2(1.0, 1.0));
    float k1 = b - a, k2 = c - a, k4 = a - b - c + d;
    float v = a + k1 * u.x + k2 * u.y + k4 * u.x * u.y;
    vec2 g = du * vec2(k1 + k4 * u.y, k2 + k4 * u.x);
    return vec3(v * 2.0 - 1.0, g * 2.0);
}

// .x = height (blocks), .yz = slope (dh/dx, dh/dz)
// Irregular water: the wave trains are bent by a slow warp so their crests are not straight, their strength
// changes from patch to patch, and two drifting noise layers break up what is left of the pattern.
vec3 chrWavesFiltered(vec2 p, float t, float footprint) {
    vec2 warp = vec2(chrWvNoise(p * 0.11 + vec2(t * 0.020, 3.7)).x,
                     chrWvNoise(p * 0.11 + vec2(-5.1, t * 0.017)).x) * 2.2;
    vec2 q = p + warp;
    // Calm and lively patches, a few dozen blocks across, slowly moving.
    float envelope = 0.55 + 0.45 * chrWvNoise(p * 0.045 + vec2(t * 0.012, -t * 0.009)).x;

    vec3 h = vec3(0.0);
    h += chrWaveTrain(q, t, normalize(vec2(0.82, 0.57)), 7.9, 0.52, 0.040) * chrWaveLod(7.9, footprint);
    h += chrWaveTrain(q, t, normalize(vec2(-0.37, 0.93)), 5.3, 0.45, 0.028) * chrWaveLod(5.3, footprint);
    h += chrWaveTrain(q, t, normalize(vec2(0.99, -0.13)), 3.7, 0.41, 0.017) * chrWaveLod(3.7, footprint);
    h += chrWaveTrain(q, t, normalize(vec2(-0.68, -0.73)), 2.9, 0.37, 0.012) * chrWaveLod(2.9, footprint);
    h += chrWaveTrain(q, t, normalize(vec2(0.31, -0.95)), 2.1, 0.33, 0.008) * chrWaveLod(2.1, footprint);
    h += chrWaveTrain(q, t, normalize(vec2(-0.96, 0.28)), 1.6, 0.29, 0.005) * chrWaveLod(1.6, footprint);

    // Drifting noise layers (choppy, no direction).
    vec3 n1 = chrWvNoise(p * 0.45 + vec2(t * 0.11, t * 0.07));
    vec3 n2 = chrWvNoise(p * 0.95 + vec2(-t * 0.16, t * 0.12) + 11.3);
    h += vec3(n1.x * 0.030, n1.yz * 0.030 * 0.45) * chrWaveLod(2.2, footprint);
    h += vec3(n2.x * 0.014, n2.yz * 0.014 * 0.95) * chrWaveLod(1.05, footprint);
    return h * envelope;
}

vec3 chrWaves(vec2 p, float t) {
    return chrWavesFiltered(p, t, 0.0);
}

#endif

#ifndef CHR_WAVES_CAUSTICS
#define CHR_WAVES_CAUSTICS
// Underwater caustics: sunlight crossing the wavy surface is focused where the surface curves up like a lens and
// spread where it curves down. p: absolute XZ where the light crossed the surface, depth: blocks of water the
// light travelled below it. Returns a brightness factor around 1 (darker 0.35, brighter up to 2.6).
// lod: drop wave trains shorter than about 4x this (0 keeps all); larger values give broader, softer patterns.
float chrCausticLod(vec2 p, float t, float depth, float lod) {
    const float e = 0.12;
    float lap = (chrWavesFiltered(p + vec2(e, 0.0), t, lod).y - chrWavesFiltered(p - vec2(e, 0.0), t, lod).y +
                 chrWavesFiltered(p + vec2(0.0, e), t, lod).z - chrWavesFiltered(p - vec2(0.0, e), t, lod).z) / (2.0 * e);
    float focus = clamp(depth, 0.0, 4.0) * 9.0;
    float intensity = 1.0 / max(1.0 + lap * focus, 0.3);
    return clamp(intensity, 0.35, 2.6);
}

float chrCaustic(vec2 p, float t, float depth) {
    return chrCausticLod(p, t, depth, 0.0);
}
#endif

#ifndef CHR_WAVES_CAUSTICS_FAST
#define CHR_WAVES_CAUSTICS_FAST
// Fast caustics: the curvature (Laplacian) of the wave trains in closed form, -a k^2 sin(phase) per train, instead
// of finite differences of the full wave field (which cost four evaluations including all the noise layers).
// Leaves out the noise layers and the slow warp, so the pattern is a slightly simpler version of the surface.
float chrCausticFast(vec2 p, float t, float depth, float lod) {
    const vec2 D0 = vec2(0.8213, 0.5705), D1 = vec2(-0.3698, 0.9291), D2 = vec2(0.9915, -0.1302);
    const vec2 D3 = vec2(-0.6817, -0.7317), D4 = vec2(0.3101, -0.9507), D5 = vec2(-0.9600, 0.2800);
    float lap = 0.0;
    vec4 wl0 = vec4(7.9, 5.3, 3.7, 2.9);
    vec2 wl1 = vec2(2.1, 1.6);
    vec4 sp0 = vec4(0.52, 0.45, 0.41, 0.37);
    vec2 sp1 = vec2(0.33, 0.29);
    vec4 am0 = vec4(0.040, 0.028, 0.017, 0.012);
    vec2 am1 = vec2(0.008, 0.005);
    vec2 dirs[6] = vec2[](D0, D1, D2, D3, D4, D5);
    float wls[6] = float[](wl0.x, wl0.y, wl0.z, wl0.w, wl1.x, wl1.y);
    float sps[6] = float[](sp0.x, sp0.y, sp0.z, sp0.w, sp1.x, sp1.y);
    float ams[6] = float[](am0.x, am0.y, am0.z, am0.w, am1.x, am1.y);
    for (int i = 0; i < 6; ++i) {
        float k = 6.2831853 / wls[i];
        float phase = dot(p, dirs[i]) * k + t * sps[i] * k;
        lap -= ams[i] * k * k * sin(phase) * chrWaveLod(wls[i], lod);
    }
    float focus = clamp(depth, 0.0, 4.0) * 9.0;
    return clamp(1.0 / max(1.0 + lap * focus, 0.3), 0.35, 2.6);
}
#endif

#ifndef CHR_WAVES_CAUSTICS_WEB
#define CHR_WAVES_CAUSTICS_WEB
// Caustics on the floor under water: the web of thin bright lines that light focused by a choppy surface draws,
// with dim cells in between. Two drifting Voronoi layers (their cell edges are the lines), bent by a slow warp so
// no cell or line repeats, and stronger or weaker from patch to patch. Normalised so the floor gets the same light
// on average as without caustics (the lines take light from the cells, they do not add any).
// p: absolute XZ where the light crossed the surface, t: seconds, depth: blocks of water below the surface.
// Returns a brightness factor around 1.

float chrCausticHash(vec2 c, uint salt) {
    uvec2 q = uvec2(ivec2(c));
    uint h = q.x * 0x8da6b343u ^ q.y * 0xd8163841u ^ salt;
    h ^= h >> 16u;
    h *= 0x7feb352du;
    h ^= h >> 15u;
    h *= 0x846ca68bu;
    h ^= h >> 16u;
    return float(h) * (1.0 / 4294967295.0);
}

// Distance from p to the nearest Voronoi cell edge (F2 - F1), cells of one unit; the cell points circle slowly.
float chrCausticEdge(vec2 p, float t, uint salt, float speed) {
    vec2 i = floor(p);
    float f1 = 9.0, f2 = 9.0;
    for (int oy = -1; oy <= 1; ++oy) {
        for (int ox = -1; ox <= 1; ++ox) {
            vec2 c = i + vec2(float(ox), float(oy));
            float a = chrCausticHash(c, salt);
            float b = chrCausticHash(c, salt ^ 0x68e31da4u);
            float ang = t * speed * (0.6 + 0.8 * b) + 6.2831853 * a;
            vec2 point = c + 0.5 + 0.38 * vec2(cos(ang), sin(ang + 1.3 * a));
            float d = length(point - p);
            f2 = d < f1 ? f1 : min(f2, d);
            f1 = min(f1, d);
        }
    }
    return f2 - f1;
}

float chrCausticWeb(vec2 p, float t, float depth) {
    // Faint in shallow water (the light has not travelled far enough to focus), fuller from about 3 blocks down.
    float strength = smoothstep(0.2, 3.5, depth) * 0.8;
    if (strength <= 0.0) { return 1.0; }
    vec2 warp = vec2(chrWvNoise(p * 0.15 + vec2(t * 0.020, 1.7)).x, chrWvNoise(p * 0.15 + vec2(-4.3, t * 0.017)).x);
    vec2 q = p + warp * 0.7;
    // Deeper water: the lines are wider and softer.
    float blur = 0.10 + 0.05 * clamp(depth, 0.0, 4.0);
    // Cells of about 1.8 blocks, and a second layer of about 2.7 blocks.
    float e1 = chrCausticEdge(q / 1.8, t, 0x2f6b9e1du, 0.35) * 1.8;
    float e2 = chrCausticEdge(q / 2.7 + vec2(0.37, 0.71), t, 0x5bd1e995u, 0.25) * 2.7;
    // Sparse: slow drifting masks let only some stretches of the lines light up, each fading in and out along its
    // length, so the floor shows scattered bright threads instead of a complete net.
    float m1 = 0.5 + 0.5 * chrWvNoise(p * 0.55 + vec2(t * 0.05 + 3.3, -t * 0.04)).x;
    float m2 = 0.5 + 0.5 * chrWvNoise(p * 0.45 + vec2(-t * 0.04 - 7.1, t * 0.05 + 2.2)).x;
    m1 = 0.08 + 0.92 * smoothstep(0.33, 0.68, m1);
    m2 = smoothstep(0.45, 0.80, m2);
    float web = exp(-0.5 * (e1 / blur) * (e1 / blur)) * m1 * 0.8 +
                exp(-0.5 * (e2 / (blur * 1.3)) * (e2 / (blur * 1.3))) * m2 * 0.6;
    web /= 0.7 * blur + 0.015;   // average of the web for this line width: normalise to 1
    // Calm and lively patches, slowly moving.
    float envelope = 0.55 + 0.45 * (0.5 + 0.5 * chrWvNoise(p * 0.07 + vec2(t * 0.010 + 9.1, -t * 0.013)).x);
    float c = 0.55 + 0.45 * web;
    return clamp(mix(1.0, c, strength * envelope), 0.3, 3.0);
}
#endif
