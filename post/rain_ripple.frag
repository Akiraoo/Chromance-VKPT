#version 460
#extension GL_GOOGLE_include_directive : require

// Rain ripples on open water, drawn as a layer over the finished picture. Radiance's denoisers keep a long history
// for calm transparent water, which froze ripples that were part of the path traced image. Here the water has
// already been denoised and upscaled; the ripples are computed for the exact world position of every water pixel
// and bend the picture like real ripples bend a reflection, with lighter and darker rings. Whatever the denoiser
// does underneath, this layer is drawn fresh every frame.
//
// Water pixels are marked by world.rgen in the segmentation mask (bit 16). Reads the copy of the frame made just
// before this pass (post_scene_color) and writes out:ldr.

#include "common/shared.hpp"
#include "lib/rain.glsl"
#include "lib/waves.glsl"
#include "lib/origin.glsl"

#ifndef CHR_POST_SCENE_BINDING
#    define CHR_POST_SCENE_BINDING 4
#endif

layout(set = 1, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};

layout(set = 1, binding = 1) uniform SkyUniform {
    SkyUBO skyUBO;
};

layout(set = 3, binding = 1) uniform sampler2D rippleDepth;   // view-space depth of the first hit, in blocks
layout(set = 3, binding = 5, r8ui) readonly uniform uimage2D segmentationMaskImage;
layout(set = 4, binding = CHR_POST_SCENE_BINDING) uniform sampler2D rippleScene;

layout(location = 0) out vec4 outColor;

const uint RIPPLE_SEGMENT_RAIN_WATER = 16u;

bool rippleIsRainWater(vec2 uv) {
    ivec2 maskSize = imageSize(segmentationMaskImage);
    if (maskSize.x <= 0 || maskSize.y <= 0) { return false; }
    ivec2 p = clamp(ivec2(uv * vec2(maskSize)), ivec2(0), maskSize - ivec2(1));
    return (imageLoad(segmentationMaskImage, p).r & RIPPLE_SEGMENT_RAIN_WATER) != 0u;
}

// Camera-relative world position of a screen point (same space as world.rgen's hitPos). Radiance hands post passes
// the first-hit depth as written by world.rgen: view-space depth in blocks.
vec3 rippleWorldPos(vec2 uv, float viewDepth) {
    vec4 viewNear = worldUBO.cameraProjMatInv * vec4(uv * 2.0 - 1.0, 0.0, 1.0);
    vec3 viewDir = viewNear.xyz / viewNear.w;
    vec3 viewPos = viewDir * (viewDepth / max(-viewDir.z, 1e-6));
    return (worldUBO.cameraEffectedViewMatInv * vec4(viewPos, 1.0)).xyz;
}

vec2 rippleProject(vec3 worldPos) {
    vec4 clip = worldUBO.cameraProjMat * (worldUBO.cameraEffectedViewMat * vec4(worldPos, 1.0));
    return clip.xy / max(clip.w, 1e-5) * 0.5 + 0.5;
}

float rippleFresnel(float cosI) {
    float f = 1.0 - clamp(cosI, 0.0, 1.0);
    return 0.02 + 0.98 * f * f * f * f * f;
}

// Rain rings, like real drops on a pond: every drop sends out a small wave packet (a Gaussian envelope over a
// short wave), so it shows as two to four concentric rings that spread and widen as they travel outwards. Drops
// differ in strength and reach, two grids of drops with different spacing overlap so they do not line up, and a
// fine, fast chop of the rain itself sits underneath. Everything is a surface slope in blocks; the picture is bent
// by it afterwards. footprint = size of one screen pixel on the water (blocks): ring detail finer than that fades
// to a soft bump instead of breaking up into moire.
vec2 rippleLayer(vec2 p, float t, float footprint, float cellSize, uint salt) {
    const float WAVELENGTH = 0.085;                      // blocks between neighbouring rings of one drop
    const float K = 6.2831853 / WAVELENGTH;
    float aa = exp(-pow(K * footprint * 0.35, 2.0));   // how much of the ring structure the pixels can show
    vec2 q = p / cellSize;
    vec2 cell = floor(q);
    vec2 slope = vec2(0.0);
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            vec2 c = cell + vec2(x, y);
            float period = mix(0.7, 2.2, chrCellHash(c, salt + 1u));
            float cycle = t / period + chrCellHash(c, salt + 2u);
            float n = floor(cycle);
            uint round = uint(int(n) & 0xffff);
            if (chrCellHash(c, salt + 3u + round * 7u) > 0.8) { continue; }
            const float life = 0.9;
            float phase = fract(cycle);
            if (phase > life) { continue; }
            float age = phase / life;
            float strengthR = mix(0.3, 1.0, chrCellHash(c, salt + 6u + round * 19u));
            float reach = cellSize * mix(0.45, 1.2, chrCellHash(c, salt + 8u + round * 23u));
            vec2 center = (c + 0.1 + 0.8 * vec2(chrCellHash(c, salt + 4u + round * 13u),
                                               chrCellHash(c, salt + 5u + round * 17u))) * cellSize;
            vec2 dp = p - center;
            float r = length(dp);
            float front = 0.015 + age * reach;
            float sigma = 0.025 + 0.07 * age;             // the packet widens: more, fainter rings later
            float xr = r - front;
            if (abs(xr) > 3.0 * sigma || r < 1e-4) { continue; }
            float env = exp(-xr * xr / (sigma * sigma));
            float fade = pow(1.0 - age, 1.6) * strengthR;
            // h = env * cos(K x): its radial derivative. Rings the pixels cannot show keep only the soft envelope.
            float ringPart = env * (-2.0 * xr / (sigma * sigma) * cos(K * xr) - K * sin(K * xr)) * aa;
            float bumpPart = env * (-2.0 * xr / (sigma * sigma)) * (1.0 - aa) * 0.6;
            float amplitude = 0.0013;
            slope += (dp / r) * (ringPart + bumpPart) * amplitude * fade;
        }
    }
    return slope;
}

vec2 rippleSlope(vec2 p, float t, float footprint) {
    vec2 slope = rippleLayer(p, t, footprint, 0.55, 0u);
    slope += rippleLayer(p + vec2(17.3, -4.1), t * 1.13, footprint, 0.38, 101u) * 0.7;
    // The rain's own fine chop: drops too small to make rings, a fast shimmer over the whole surface.
    float chopAA = 1.0 - smoothstep(0.03, 0.12, footprint);
    vec3 n1 = chrWvNoise(p * 5.0 + vec2(t * 0.9, -t * 0.7));
    vec3 n2 = chrWvNoise(p * 9.0 + vec2(-t * 1.3, t * 1.1) + 7.7);
    slope += (n1.yz * 5.0 * 0.0016 + n2.yz * 9.0 * 0.0007) * chopAA;
    return slope;
}

void main() {
    ivec2 size = textureSize(rippleScene, 0);
    ivec2 pixel = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    vec4 scene = texelFetch(rippleScene, pixel, 0);
    outColor = scene;

    float rain = clamp(skyUBO.rainGradient, 0.0, 1.0);
    float strength = max(float(CHR_RIPPLE_STRENGTH), 0.0) * rain;
    if (strength <= 0.001 || worldUBO.skyType != 1u) { return; }

    vec2 uv = (vec2(pixel) + 0.5) / vec2(size);
    if (!rippleIsRainWater(uv)) { return; }
    float depth = texture(rippleDepth, uv).r;
    if (!(depth > 0.0) || depth > 4096.0) { return; }

    vec3 worldPos = rippleWorldPos(uv, depth);
    vec3 absPos = worldPos + chrWrappedCamera(worldUBO.cameraPos.xyz);
    vec3 eye = vec3(worldUBO.cameraEffectedViewMatInv * vec4(0.0, 0.0, 0.0, 1.0));
    vec3 toEye = eye - worldPos;
    float dist = length(toEye);
    vec3 v = toEye / max(dist, 1e-4);
    float fade = 1.0 - smoothstep(16.0, 48.0, dist);
    if (fade <= 0.0) { return; }

    // One screen pixel measured on the water surface (it stretches at grazing angles).
    float pixelAngle = 2.0 / (abs(worldUBO.cameraProjMat[1][1]) * float(size.y));
    float footprint = dist * pixelAngle / max(abs(v.y), 0.08);

    vec2 slope = rippleSlope(absPos.xz, worldUBO.gameTime * 1200.0, footprint) * min(strength, 2.0) * fade;
    if (dot(slope, slope) < 1e-8) { return; }

    // Real ripples barely show colour of their own: they bend what the water reflects and shows through. Shift the
    // picture by the ripple slope and add the slight Fresnel brightening / darkening of the tilted ring sides.
    vec2 shiftedUv = rippleProject(worldPos + vec3(slope.x, 0.0, slope.y) * 0.8);
    vec3 color = scene.rgb;
    if (all(greaterThanEqual(shiftedUv, vec2(0.0))) && all(lessThanEqual(shiftedUv, vec2(1.0))) &&
        rippleIsRainWater(shiftedUv)) {
        color = texture(rippleScene, shiftedUv).rgb;
    }
    vec3 rippleN = normalize(vec3(-slope.x, 1.0, -slope.y));
    float cosFlat = abs(v.y);
    float delta = rippleFresnel(abs(dot(rippleN, v))) - rippleFresnel(cosFlat);
    color *= clamp(1.0 + delta * 3.0, 0.85, 1.25);
    outColor = vec4(clamp(color, vec3(0.0), vec3(1.0)), scene.a);
}
