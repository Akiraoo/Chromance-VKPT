#ifndef CHR_WATER_GLSL
#define CHR_WATER_GLSL

// Water surface and volume. Batch 1 keeps this simple (gentle animated waves, absorption by depth); the two
// selectable water styles arrive with the water update.

const float CHR_WATER_IOR = 1.333;
const float CHR_WATER_ORIGIN_BIAS = 0.0008;

// Absorption per block. Red goes first, which turns deep water blue-green.
vec3 chrWaterAbsorption() {
    // Real water, one block = one metre: red is gone within about 5 m, orange and yellow by 10-20 m, green by about
    // 30 m, and cyan and blue reach deepest. Slightly gentler than real water (a little warmth stays in shallow
    // riverbeds), in the same order, so depth turns things green-cyan and then blue instead of one flat blue.
    return vec3(0.22, 0.052, 0.032) * max(float(CHR_WATER_FOG_DENSITY), 0.0);
}

// Water coloured by its biome (swamps murky green, warm oceans turquoise, cold oceans deep blue). The biome water
// colour is Minecraft's own per-biome value, carried by the water surface's vertex colour. Ordinary water
// (Minecraft's default colour, used by rivers, plains and most oceans) keeps the pack's natural absorption above;
// other biomes only shift it by how far their colour differs from that default. Using the biome colour directly
// made all ordinary water a saturated deep blue. CHR_WATER_BIOME_TINT scales the shift.
const vec3 CHR_DEFAULT_WATER_COLOR = vec3(0.247, 0.463, 0.894);   // Minecraft's default water colour, #3F76E4

vec3 chrWaterAbsorptionTinted(uint packedTint) {
    vec3 neutral = chrWaterAbsorption();
    if (packedTint == 0u) { return neutral; }
    vec3 c = clamp(unpackUnorm4x8(packedTint).rgb, vec3(0.05), vec3(1.0));   // 24-bit RGB in the low bytes
    vec3 shift = (log(CHR_DEFAULT_WATER_COLOR) - log(c)) * 0.075 * max(float(CHR_WATER_FOG_DENSITY), 0.0);
    return max(neutral + shift * clamp(float(CHR_WATER_BIOME_TINT), 0.0, 1.0) * 1.4, vec3(0.004));
}

uint chrPackWaterTint(vec3 c) {
    // Untinted (white) means there was no biome colour to read.
    if (min(c.r, min(c.g, c.b)) > 0.97) { return 0u; }
    return packUnorm4x8(vec4(clamp(c, vec3(0.0), vec3(1.0)), 0.0));  // alpha 0: only the low 24 bits are used
}

float chrWaveHash(vec2 p) {
    // Integer hash: exact for any block coordinate (a sin hash loses precision on coordinates in the thousands).
    uvec2 q = uvec2(ivec2(floor(p)));
    uint h = q.x * 0x8da6b343u ^ q.y * 0xd8163841u ^ 0x5bd1e995u;
    h ^= h >> 16u;
    h *= 0x7feb352du;
    h ^= h >> 15u;
    h *= 0x846ca68bu;
    h ^= h >> 16u;
    return float(h) * (1.0 / 4294967295.0);
}

float chrWaveNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = chrWaveHash(i);
    float b = chrWaveHash(i + vec2(1.0, 0.0));
    float c = chrWaveHash(i + vec2(0.0, 1.0));
    float d = chrWaveHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float chrWaveHeight(vec2 p, float t) {
    float h = 0.0;
    h += sin(dot(p, vec2(0.80, 0.60)) * 1.3 + t * 1.10) * 0.050;
    h += sin(dot(p, vec2(-0.45, 0.89)) * 2.1 + t * 1.55) * 0.030;
    h += sin(dot(p, vec2(0.97, -0.24)) * 3.4 + t * 2.10) * 0.016;
    h += (chrWaveNoise(p * 1.7 + vec2(t * 0.35, t * 0.22)) - 0.5) * 0.050;
    h += (chrWaveNoise(p * 4.3 - vec2(t * 0.55, -t * 0.40)) - 0.5) * 0.020;
    return h;
}

// World-space normal of the water surface at an absolute position (XZ). Only used for upward facing surfaces.
vec3 chrWaterNormal(vec2 p, float gameTime, float distanceToCamera) {
    float strength = max(float(CHR_WATER_WAVE_STRENGTH), 0.0);
    // Fade small waves with distance so far water does not shimmer.
    strength *= 1.0 - smoothstep(24.0, 96.0, distanceToCamera) * 0.8;
    if (strength <= 0.0) { return vec3(0.0, 1.0, 0.0); }
    float t = gameTime * 1200.0;   // gameTime is the day fraction
    const float e = 0.05;
    float h = chrWaveHeight(p, t);
    float hx = chrWaveHeight(p + vec2(e, 0.0), t);
    float hz = chrWaveHeight(p + vec2(0.0, e), t);
    vec2 slope = vec2(hx - h, hz - h) / e * strength;
    return normalize(vec3(-slope.x, 1.0, -slope.y));
}

#endif
