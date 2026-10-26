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

// Brightness of the ring lines (0..1) at a water point. Same drops and timing as chrRippleSlope in lib/rain.glsl,
// but drawn as soft lines. footprint = size of one screen pixel on the water, in blocks: rings are widened to at
// least that and dimmed to match, so they never break up into the moire pattern of lines thinner than a pixel.
float rippleRings(vec2 p, float t, float footprint) {
    float width = max(0.018, footprint * 0.75);
    float energy = 0.018 / width;
    float result = 0.0;
    vec2 cell = floor(p);
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            vec2 c = cell + vec2(x, y);
            float period = mix(1.1, 2.6, chrCellHash(c, 1u));
            float cycle = t / period + chrCellHash(c, 2u);
            float n = floor(cycle);
            float phase = fract(cycle);
            uint round = uint(int(n) & 0xffff);
            if (chrCellHash(c, 3u + round * 7u) > 0.7) { continue; }
            const float life = 0.85;
            if (phase > life) { continue; }
            float age = phase / life;
            vec2 center = c + 0.1 + 0.8 * vec2(chrCellHash(c, 4u + round * 13u), chrCellHash(c, 5u + round * 17u));
            float r = length(p - center);
            float front = age * 0.95;
            float fade = (1.0 - age) * (1.0 - age);
            // Two soft rings: the leading one and a fainter one behind it.
            for (int k = 0; k < 2; ++k) {
                float ringR = front - float(k) * 0.11;
                if (ringR <= 0.0) { continue; }
                float d = (r - ringR) / width;
                result += exp(-d * d) * fade * (k == 0 ? 1.0 : 0.5);
            }
        }
    }
    return clamp(result * energy, 0.0, 1.0);
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

    float rings = rippleRings(absPos.xz, worldUBO.gameTime * 1200.0, footprint) * min(strength, 2.0) * fade;
    if (rings <= 1e-4) { return; }

    // Faint light-blue lines, like the sky caught on the edge of each ring. Brighter on bright water, never harsh.
    vec3 tint = vec3(0.72, 0.86, 1.0);
    float base = 0.22 + 0.45 * dot(scene.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 color = scene.rgb + tint * rings * base * 0.6;
    outColor = vec4(clamp(color, vec3(0.0), vec3(1.0)), scene.a);
}
