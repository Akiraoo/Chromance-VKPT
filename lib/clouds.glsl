#ifndef CHR_CLOUDS_GLSL
#define CHR_CLOUDS_GLSL

// Volumetric clouds.
//
// One cloud layer between CHR_CLOUD_BOTTOM and CHR_CLOUD_TOP (absolute world height). In fair weather it is made of
// scattered, puffy cumulus; as rain sets in the gaps close and the clouds flatten into a low, grey stratus deck.
// The shape comes from two tiling 3D noise volumes (a Perlin-Worley "shape" noise and a Worley "detail" noise,
// both taken from Radiance's Vanilla PT, GPL-3.0) and a 2D coverage field.
//
// Everything that moves is periodic: the wind carries the clouds exactly one noise tile (1200 blocks) per 1200
// seconds, the length of Minecraft's 20-minute game-time cycle, so the clouds do not jump when gameTime wraps.
//
// Requires: worldUBO, skyUBO, lib/palette.glsl, lib/settings.glsl.

#ifndef CHR_CLOUD_TEX_SET
#    define CHR_CLOUD_TEX_SET 5
#endif
#ifndef CHR_CLOUD_SHAPE_BINDING
#    define CHR_CLOUD_SHAPE_BINDING 7
#endif
#ifndef CHR_CLOUD_DETAIL_BINDING
#    define CHR_CLOUD_DETAIL_BINDING 8
#endif

layout(set = CHR_CLOUD_TEX_SET, binding = CHR_CLOUD_SHAPE_BINDING) uniform sampler3D chrCloudShapeNoise;
layout(set = CHR_CLOUD_TEX_SET, binding = CHR_CLOUD_DETAIL_BINDING) uniform sampler3D chrCloudDetailNoise;

const float CHR_CLOUD_BOTTOM = 200.0;
const float CHR_CLOUD_TOP = 330.0;
const float CHR_CLOUD_MID = 0.5 * (CHR_CLOUD_BOTTOM + CHR_CLOUD_TOP);
const float CHR_CLOUD_TILE = 1200.0;          // every noise repeats after this many blocks
const float CHR_CLOUD_SIGMA = 0.045;          // extinction per block at density 1
const float CHR_CLOUD_MAX_DISTANCE = 9000.0;

float chrCloudSat(float x) { return clamp(x, 0.0, 1.0); }

float chrCloudRemap(float v, float lo, float hi, float newLo, float newHi) {
    return newLo + (clamp(v, lo, hi) - lo) / max(hi - lo, 1e-5) * (newHi - newLo);
}

// Seconds on the 20-minute game-time cycle.
float chrCloudTime() {
    return worldUBO.gameTime * 1200.0;
}

// How rainy the sky looks: 0 fair weather (cumulus), 1 full overcast (stratus).
float chrCloudRain() {
    return smoothstep(0.05, 0.85, clamp(skyUBO.rainGradient, 0.0, 1.0));
}

// Periodic value noise on a lattice of `period` cells.
float chrCloudHash(ivec2 c) {
    uvec2 q = uvec2(c);
    uint h = q.x * 0x8da6b343u ^ q.y * 0xd8163841u ^ 0x2545f491u;
    h ^= h >> 16u;
    h *= 0x7feb352du;
    h ^= h >> 15u;
    h *= 0x846ca68bu;
    h ^= h >> 16u;
    return float(h) * (1.0 / 4294967295.0);
}

float chrCloudValueNoise(vec2 p, int period) {
    vec2 i = floor(p);
    vec2 f = p - i;
    vec2 u = f * f * (3.0 - 2.0 * f);
    ivec2 c = ivec2(i);
    ivec2 c00 = ivec2((c.x % period + period) % period, (c.y % period + period) % period);
    ivec2 c11 = ivec2(((c.x + 1) % period + period) % period, ((c.y + 1) % period + period) % period);
    float a = chrCloudHash(c00);
    float b = chrCloudHash(ivec2(c11.x, c00.y));
    float d = chrCloudHash(ivec2(c00.x, c11.y));
    float e = chrCloudHash(c11);
    return mix(mix(a, b, u.x), mix(d, e, u.x), u.y);
}

// Absolute world position moved back along the wind (the clouds drift towards +X).
vec3 chrCloudWind(vec3 p) {
    return p - vec3(chrCloudTime() * (CHR_CLOUD_TILE / 1200.0), 0.0, 0.0);
}

// 2D coverage field (0..1) at a wind-shifted position.
float chrCloudCoverageField(vec2 xz) {
    vec2 q = xz / CHR_CLOUD_TILE;
    float n = chrCloudValueNoise(q * 6.0, 6) * 0.55 + chrCloudValueNoise(q * 14.0 + 3.1, 14) * 0.30 +
              chrCloudValueNoise(q * 31.0 + 7.7, 31) * 0.15;
    return n;
}

// Cloud density (0..1) at an absolute world position.
float chrCloudDensity(vec3 pAbs, bool cheap) {
    float h01 = (pAbs.y - CHR_CLOUD_BOTTOM) / (CHR_CLOUD_TOP - CHR_CLOUD_BOTTOM);
    if (h01 <= 0.0 || h01 >= 1.0) { return 0.0; }
    float rain = chrCloudRain();
    vec3 p = chrCloudWind(pAbs);

    // Height profiles: cumulus rounded with a flat base, stratus a thin low sheet.
    float cumulus = smoothstep(0.0, 0.08, h01) * (1.0 - smoothstep(0.35, 1.0, h01));
    float stratus = smoothstep(0.0, 0.05, h01) * (1.0 - smoothstep(0.18, 0.42, h01));
    float profile = mix(cumulus, stratus, rain);
    if (profile <= 0.0) { return 0.0; }

    float coverage = mix(clamp(float(CHR_CLOUD_COVERAGE), 0.0, 1.0), 0.97, rain);
    float field = chrCloudCoverageField(p.xz);
    float cov = chrCloudSat(chrCloudRemap(field, 1.0 - coverage, 1.0 - coverage + 0.35, 0.0, 1.0));
    if (cov <= 0.0) { return 0.0; }

    float shape = texture(chrCloudShapeNoise, p.xzy / CHR_CLOUD_TILE * vec3(2.0, 2.0, 2.0)).r;
    float base = chrCloudRemap(shape * profile, 1.0 - cov * mix(0.85, 1.0, rain), 1.0, 0.0, 1.0);
    if (base <= 0.0) { return 0.0; }
    if (cheap) { return base; }

    // Erode the edges with the detail noise (wispy at the bottom, billowy at the top).
    vec3 dp = (p + vec3(0.0, chrCloudTime() * 0.05, 0.0)) / CHR_CLOUD_TILE * 20.0;
    float detail = texture(chrCloudDetailNoise, dp.xzy).r;
    float erosion = mix(detail, 1.0 - detail, chrCloudSat(h01 * 4.0)) * mix(0.35, 0.2, rain);
    return chrCloudSat(chrCloudRemap(base, erosion, 1.0, 0.0, 1.0)) * mix(1.0, 0.75, rain);
}

float chrCloudHG(float g, float c) {
    float g2 = g * g;
    return (1.0 - g2) / (12.566371 * pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5));
}

// Optical depth from a point towards the light (a few growing steps).
float chrCloudLightDepth(vec3 pAbs, vec3 L) {
    float od = 0.0;
    float t = 0.0;
    float step = 11.0;
    for (int i = 0; i < 4; ++i) {
        t += step;
        vec3 q = pAbs + L * (t - 0.5 * step);
        od += chrCloudDensity(q, true) * step;
        step *= 1.7;
    }
    return od * CHR_CLOUD_SIGMA;
}

struct ChrCloudResult {
    vec3 scatter;          // light added by the clouds
    float transmittance;   // how much of what is behind still shows
};

// Raymarches the cloud layer along a ray. originRel: camera-relative ray origin, dir: normalized direction.
// steps: view samples, jitter: 0..1 offset of the first sample.
ChrCloudResult chrCloudMarch(ChrPalette pal, vec3 originRel, vec3 dir, int steps, float jitter) {
    ChrCloudResult r;
    r.scatter = vec3(0.0);
    r.transmittance = 1.0;

    vec3 o = originRel + vec3(worldUBO.cameraPos.xyz);
    if (abs(dir.y) < 1e-4) { return r; }
    float t0 = (CHR_CLOUD_BOTTOM - o.y) / dir.y;
    float t1 = (CHR_CLOUD_TOP - o.y) / dir.y;
    if (t0 > t1) { float tmp = t0; t0 = t1; t1 = tmp; }
    t0 = max(t0, 0.0);
    if (t1 <= t0) { return r; }
    t1 = min(t1, t0 + 1200.0);   // grazing rays: march only the nearer part of the slab
    if (t0 > CHR_CLOUD_MAX_DISTANCE) { return r; }

    vec3 L = pal.lightDir;
    float cosTheta = dot(dir, L);
    // Bright forward lobe (silver lining), a softer back lobe.
    float phase = mix(chrCloudHG(-0.15, cosTheta), chrCloudHG(0.65, cosTheta), 0.6);
    vec3 sun = pal.lightColor;
    float rain = chrCloudRain();
    vec3 ambientTop = pal.zenith * 1.1 + pal.horizon * 0.25;
    vec3 ambientBottom = mix(pal.horizon * 0.5, pal.zenith * 0.45, 0.5);

    float dt = (t1 - t0) / float(steps);
    float T = 1.0;
    vec3 S = vec3(0.0);
    for (int i = 0; i < steps; ++i) {
        float t = t0 + (float(i) + jitter) * dt;
        vec3 p = o + dir * t;
        float d = chrCloudDensity(p, false);
        if (d <= 0.002) { continue; }
        float h01 = chrCloudSat((p.y - CHR_CLOUD_BOTTOM) / (CHR_CLOUD_TOP - CHR_CLOUD_BOTTOM));
        float lightOd = sun == vec3(0.0) ? 0.0 : chrCloudLightDepth(p, L);
        // Beer's law with a multiple-scattering tail and a "powder" darkening of the thin outer edges.
        float beer = max(exp(-lightOd), exp(-lightOd * 0.25) * 0.7);
        float powder = 1.0 - exp(-d * 18.0);
        vec3 lit = sun * beer * phase * 12.566 * 0.32 * mix(1.0, powder, 0.6);
        vec3 ambient = mix(ambientBottom, ambientTop, h01) * mix(1.0, 0.6, rain);
        vec3 src = lit + ambient;
        float sigma = d * CHR_CLOUD_SIGMA * mix(1.0, 1.6, rain);
        float stepT = exp(-sigma * dt);
        S += T * src * (1.0 - stepT);
        T *= stepT;
        if (T < 0.01) { break; }
    }
    // Fade far clouds into the sky so the layer does not end in a hard line at the horizon.
    float fade = 1.0 - smoothstep(CHR_CLOUD_MAX_DISTANCE * 0.35, CHR_CLOUD_MAX_DISTANCE, t0);
    r.scatter = S * fade;
    r.transmittance = mix(1.0, T, fade);
    return r;
}

// ---- Cloud shadow map -------------------------------------------------------------------------------------------
// A top-down map of how much sunlight the clouds let through, CHR_CLOUD_SHADOW_RANGE blocks across, centred on the
// camera (snapped to whole blocks so it does not shimmer). Each texel holds the transmittance along the light
// through the cloud layer, for the light ray that crosses the layer's middle height at that texel.

const float CHR_CLOUD_SHADOW_RANGE = 2048.0;

vec2 chrCloudShadowCentre() {
    return floor(vec2(worldUBO.cameraPos.xz) / 8.0) * 8.0;
}

// Transmittance for the light ray through the cloud layer that crosses mid height at absolute XZ.
float chrCloudShadowRayN(vec2 midXZ, vec3 L, int N) {
    if (L.y < 0.05) { return 1.0; }
    vec3 mid = vec3(midXZ.x, CHR_CLOUD_MID, midXZ.y);
    float tA = (CHR_CLOUD_BOTTOM - CHR_CLOUD_MID) / L.y;
    float tB = (CHR_CLOUD_TOP - CHR_CLOUD_MID) / L.y;
    float dt = (tB - tA) / float(N);
    float od = 0.0;
    for (int i = 0; i < N; ++i) {
        od += chrCloudDensity(mid + L * (tA + (float(i) + 0.5) * dt), true) * dt;
    }
    return exp(-od * CHR_CLOUD_SIGMA * 2.0);
}

float chrCloudShadowRay(vec2 midXZ, vec3 L) {
    return chrCloudShadowRayN(midXZ, L, 10);
}

#ifdef CHR_CLOUD_SHADOW_LOOKUP
#ifndef CHR_CLOUD_SHADOW_BINDING
#    define CHR_CLOUD_SHADOW_BINDING 9
#endif
layout(set = CHR_CLOUD_TEX_SET, binding = CHR_CLOUD_SHADOW_BINDING) uniform sampler2D chrCloudShadowMap;

// Sunlight let through by the clouds at a camera-relative position (1 = no cloud).
float chrCloudShadowAt(vec3 pRel, vec3 L) {
    if (L.y < 0.05) { return 1.0; }
    vec3 pAbs = pRel + vec3(worldUBO.cameraPos.xyz);
    if (pAbs.y > CHR_CLOUD_MID) { return 1.0; }
    vec2 midXZ = pAbs.xz + L.xz * ((CHR_CLOUD_MID - pAbs.y) / L.y);
    // Read from the cloud shadow map rendered once per frame (sky/cloud_shadow.frag): one texture fetch instead of
    // marching the clouds again for every light sample.
    vec2 uv = (midXZ - chrCloudShadowCentre()) / CHR_CLOUD_SHADOW_RANGE + 0.5;
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { return 1.0; }
    float t = texture(chrCloudShadowMap, uv).r;
    return mix(1.0, t, clamp(float(CHR_CLOUD_SHADOW_STRENGTH), 0.0, 1.0));
}
#endif

#endif
