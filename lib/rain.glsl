#ifndef CHR_RAIN_GLSL
#define CHR_RAIN_GLSL

// Wet ground in rain: darker, glossier surfaces, mirror-like puddles in low spots, and animated ripples where
// drops land. Only surfaces open to the sky (vanilla sky light level 14-15) get wet.

#ifndef CHR_RAIN_WETNESS
#    define CHR_RAIN_WETNESS 1
#endif
#ifndef CHR_PUDDLE_AMOUNT
#    define CHR_PUDDLE_AMOUNT 0.5
#endif
#ifndef CHR_RIPPLE_STRENGTH
#    define CHR_RIPPLE_STRENGTH 1.0
#endif

// Integer hash of a lattice point. (A sin/fract hash fed with world coordinates in the thousands ran out of float
// precision: its values came out correlated and the puddles turned into long diagonal streaks.)
float chrRainHash(vec2 p) {
    uvec2 q = uvec2(ivec2(floor(p)));
    uint h = q.x * 0x8da6b343u ^ q.y * 0xd8163841u ^ 0x2f6b9e1du;
    h ^= h >> 16u;
    h *= 0x7feb352du;
    h ^= h >> 15u;
    h *= 0x846ca68bu;
    h ^= h >> 16u;
    return float(h) * (1.0 / 4294967295.0);
}

float chrRainNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(chrRainHash(i), chrRainHash(i + vec2(1.0, 0.0)), u.x),
               mix(chrRainHash(i + vec2(0.0, 1.0)), chrRainHash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 0 = damp, 1 = standing water. Large soft blobs that stay put in the world.
float chrPuddleMask(vec2 p) {
    float n = chrRainNoise(p * 0.11) * 0.65 + chrRainNoise(p * 0.37 + 7.3) * 0.35;
    float amount = clamp(float(CHR_PUDDLE_AMOUNT), 0.0, 1.0);
    float threshold = mix(0.85, 0.30, amount);
    return smoothstep(threshold, threshold + 0.08, n);
}

// Integer hash of a block cell plus a salt, so neighbouring blocks get unrelated random values.
float chrCellHash(vec2 cell, uint salt) {
    uvec2 q = uvec2(ivec2(cell));
    uint h = q.x * 0x8da6b343u ^ q.y * 0xd8163841u ^ salt * 0xcb1ab31fu;
    h ^= h >> 16u;
    h *= 0x7feb352du;
    h ^= h >> 15u;
    h *= 0x846ca68bu;
    h ^= h >> 16u;
    return float(h) * (1.0 / 4294967295.0);
}

// Slope of raindrop ripples (XZ). Every block is its own drop site with its own random rhythm: it waits, a drop lands
// at a random spot and sends out a train of three to four concentric rings that spread up to about a block and
// fade, then it waits again. About 7 in 10 rounds have a drop. Rings from neighbouring blocks overlap.
vec2 chrRippleSlope(vec2 p, float t) {
    vec2 slope = vec2(0.0);
    vec2 cell = floor(p);
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            vec2 c = cell + vec2(x, y);
            float period = mix(1.1, 2.6, chrCellHash(c, 1u));   // seconds between drops, per block
            float cycle = t / period + chrCellHash(c, 2u);        // random offset: blocks never pulse together
            float n = floor(cycle);
            float phase = fract(cycle);
            uint round = uint(int(n) & 0xffff);
            if (chrCellHash(c, 3u + round * 7u) > 0.7) { continue; }
            const float life = 0.85;
            if (phase > life) { continue; }
            float age = phase / life;
            vec2 center = c + 0.1 + 0.8 * vec2(chrCellHash(c, 4u + round * 13u), chrCellHash(c, 5u + round * 17u));
            vec2 d = p - center;
            float r = length(d);
            float front = age * 0.95;                 // leading ring radius in blocks
            float behind = front - r;                 // distance behind the leading ring
            if (behind < -0.05 || behind > 0.32) { continue; }
            // Wave train: crests every ~0.08 blocks behind the front, strongest at the front.
            float train = sin(behind * 78.0) * exp(-max(behind, 0.0) * 9.0) * smoothstep(-0.05, 0.0, behind);
            float fade = (1.0 - age) * (1.0 - age) * smoothstep(0.0, 0.06, r);
            slope += (r > 1e-4 ? d / r : vec2(0.0)) * train * fade;
        }
    }
    return slope * 1.4;
}

struct ChrWetness {
    float wet;      // 0..1 overall wetness
    float puddle;   // 0..1 standing water
    float film;     // 0..1 water film on top faces
    vec3 normal;    // shading normal including ripples
};

// p: absolute world position, ng: geometric normal, n: shading normal, skyLight: 0..15
// rain: how wet (may lag behind the weather while drying), rippleRain: how hard it is raining right now.
ChrWetness chrRainWetness(vec3 p, vec3 ng, vec3 n, float skyLight, float rain, float rippleRain, float gameTime, bool primary) {
    ChrWetness w;
    w.wet = 0.0;
    w.puddle = 0.0;
    w.film = 0.0;
    w.normal = n;
#if CHR_RAIN_WETNESS
    float exposed = smoothstep(12.5, 14.5, skyLight);
    w.wet = rain * exposed;
    if (w.wet <= 0.001) { return w; }
    float up = smoothstep(0.6, 0.95, ng.y);
    w.puddle = chrPuddleMask(p.xz) * up * smoothstep(0.3, 0.9, rain) * exposed;
    // Every exposed top face carries a thin water film that reflects like a mirror; puddles only add depth.
    w.film = up * smoothstep(0.15, 0.6, rain) * exposed;
    if (primary && up > 0.0) {
        vec2 s = chrRippleSlope(p.xz, gameTime * 1200.0) * max(float(CHR_RIPPLE_STRENGTH), 0.0) * rippleRain * exposed;
        vec3 rippleN = normalize(vec3(-s.x, 1.0, -s.y));
        // Puddles take the ripples on a flat water surface; damp ground keeps its own detail.
        // The film smooths out the block's own bumps; ripples ride on top of it.
        float flatness = max(w.puddle, w.film * 0.7);
        w.normal = normalize(mix(n, rippleN, flatness));
    } else {
        w.normal = normalize(mix(n, vec3(0.0, 1.0, 0.0), max(w.puddle, w.film * 0.7)));
    }
#endif
    return w;
}

#endif
