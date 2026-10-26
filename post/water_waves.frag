#version 460
#extension GL_GOOGLE_include_directive : require

// Water waves as a layer over the finished picture (setting "Water Waves"). The path traced water stays flat, so
// Radiance's denoiser keeps it clean and stable; here every water pixel is pushed around by a few long, slowly
// drifting waves, which bends both the reflection and the view into the water, and the wave slopes add soft
// lighter and darker bands. Works from above and from below the surface.
//
// Water pixels are marked by world.rgen in the segmentation mask (bit 32). Reads the copy of the frame made just
// before this pass (post_scene_color) and writes out:ldr.

#include "common/shared.hpp"
#include "lib/waves.glsl"

#ifndef CHR_POST_SCENE_BINDING
#    define CHR_POST_SCENE_BINDING 4
#endif
#ifndef CHR_WATER_WAVE_OVERLAY_STRENGTH
#    define CHR_WATER_WAVE_OVERLAY_STRENGTH 1.0
#endif

layout(set = 1, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};

layout(set = 1, binding = 1) uniform SkyUniform {
    SkyUBO skyUBO;
};

layout(set = 3, binding = 1) uniform sampler2D waveDepth;   // view-space depth of the first hit, in blocks
layout(set = 3, binding = 5, r8ui) readonly uniform uimage2D segmentationMaskImage;
layout(set = 4, binding = CHR_POST_SCENE_BINDING) uniform sampler2D waveScene;

layout(location = 0) out vec4 outColor;

const uint WAVE_SEGMENT_WATER = 32u;

bool waveIsWater(vec2 uv) {
    ivec2 maskSize = imageSize(segmentationMaskImage);
    if (maskSize.x <= 0 || maskSize.y <= 0) { return false; }
    ivec2 p = clamp(ivec2(uv * vec2(maskSize)), ivec2(0), maskSize - ivec2(1));
    return (imageLoad(segmentationMaskImage, p).r & WAVE_SEGMENT_WATER) != 0u;
}

vec3 waveWorldPos(vec2 uv, float viewDepth) {
    vec4 viewNear = worldUBO.cameraProjMatInv * vec4(uv * 2.0 - 1.0, 0.0, 1.0);
    vec3 viewDir = viewNear.xyz / viewNear.w;
    vec3 viewPos = viewDir * (viewDepth / max(-viewDir.z, 1e-6));
    return (worldUBO.cameraEffectedViewMatInv * vec4(viewPos, 1.0)).xyz;
}

vec2 waveProject(vec3 worldPos) {
    vec4 clip = worldUBO.cameraProjMat * (worldUBO.cameraEffectedViewMat * vec4(worldPos, 1.0));
    return clip.xy / max(clip.w, 1e-5) * 0.5 + 0.5;
}

float waveFresnel(float cosI) {
    float f = 1.0 - clamp(cosI, 0.0, 1.0);
    return 0.02 + 0.98 * f * f * f * f * f;
}

void main() {
    ivec2 size = textureSize(waveScene, 0);
    ivec2 pixel = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    vec4 scene = texelFetch(waveScene, pixel, 0);
    outColor = scene;

    float strength = max(float(CHR_WATER_WAVE_OVERLAY_STRENGTH), 0.0);
    if (strength <= 0.001) { return; }

    vec2 uv = (vec2(pixel) + 0.5) / vec2(size);
    if (!waveIsWater(uv)) { return; }
    float depth = texture(waveDepth, uv).r;
    if (!(depth > 0.0) || depth > 4096.0) { return; }

    vec3 worldPos = waveWorldPos(uv, depth);
    vec3 absPos = worldPos + vec3(worldUBO.cameraPos.xyz);
    vec3 eye = vec3(worldUBO.cameraEffectedViewMatInv * vec4(0.0, 0.0, 0.0, 1.0));
    vec3 toEye = eye - worldPos;
    float dist = length(toEye);
    vec3 v = toEye / max(dist, 1e-4);
    float fade = 1.0 - smoothstep(20.0, 56.0, dist);
    // Looking along the surface at a shallow angle the waves pile up into thin bands; ease them out there.
    float grazing = smoothstep(0.04, 0.22, abs(v.y));
    fade *= grazing;
    if (fade <= 0.0) { return; }

    // One screen pixel measured on the water surface (it stretches at grazing angles).
    float pixelAngle = 2.0 / (abs(worldUBO.cameraProjMat[1][1]) * float(size.y));
    float footprint = dist * pixelAngle / max(abs(v.y), 0.05);

    vec2 slope = chrWavesFiltered(absPos.xz, worldUBO.gameTime * 1200.0, footprint).yz * strength * fade;
    bool fromBelow = skyUBO.cameraSubmersionType == 1u;

    // Bend the picture by a small, fixed amount in the world.
    float shiftAmount = 0.9;
    vec2 shiftedUv = waveProject(worldPos + vec3(slope.x, 0.0, slope.y) * shiftAmount);
    vec3 color = scene.rgb;
    if (all(greaterThanEqual(shiftedUv, vec2(0.0))) && all(lessThanEqual(shiftedUv, vec2(1.0))) &&
        waveIsWater(shiftedUv)) {
        color = texture(waveScene, shiftedUv).rgb;
    }

    // Soft bands: wave sides facing the viewer reflect a little less, the far sides a little more.
    vec3 waveN = normalize(vec3(-slope.x, 1.0, -slope.y));
    float cosFlat = abs(v.y);
    float cosWave = abs(dot(waveN, v));
    float delta = waveFresnel(cosWave) - waveFresnel(cosFlat);
    float shade = clamp(1.0 + delta * (fromBelow ? 1.5 : 2.5), 0.85, 1.2);
    color *= shade;

    outColor = vec4(clamp(color, vec3(0.0), vec3(1.0)), scene.a);
}
