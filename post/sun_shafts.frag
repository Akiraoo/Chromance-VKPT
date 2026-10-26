#version 460
#extension GL_GOOGLE_include_directive : require

// Screen-space sun shafts. Bright beams that fan out from the sun (or moon) wherever the sky shows between
// mountains, trees and buildings: for every pixel, march towards the sun's position on screen and gather how much
// open sky lies along the way. Cheap and high contrast, it complements the path-traced haze shafts, which are too
// soft to show distinct beams at this sample count. Fades out as the sun leaves the screen, in rain and behind
// thick cloud.

#include "common/shared.hpp"

#ifndef CHR_POST_SCENE_BINDING
#    define CHR_POST_SCENE_BINDING 4
#endif
#ifndef CHR_AIR_GOD_RAYS
#    define CHR_AIR_GOD_RAYS 0.5
#endif

layout(set = 1, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};
layout(set = 1, binding = 1) uniform SkyUniform {
    SkyUBO skyUBO;
};

layout(set = 3, binding = 5, r8ui) readonly uniform uimage2D segmentationMaskImage;
layout(set = 4, binding = CHR_POST_SCENE_BINDING) uniform sampler2D shaftScene;

layout(location = 0) out vec4 outColor;

float shaftHash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// 1 where open sky shows (not covered by geometry or thick volumetric cloud).
float shaftSky(vec2 uv, ivec2 res) {
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { return 0.0; }
    ivec2 p = clamp(ivec2(uv * vec2(res)), ivec2(0), res - ivec2(1));
    uint s = imageLoad(segmentationMaskImage, p).r;
    if ((s & 2u) == 0u) { return 0.0; }
    return (s & 64u) != 0u ? 0.25 : 1.0;
}

void main() {
    ivec2 size = textureSize(shaftScene, 0);
    ivec2 pixel = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    vec4 scene = texelFetch(shaftScene, pixel, 0);
    outColor = scene;

    float amount = max(float(CHR_AIR_GOD_RAYS), 0.0);
    if (amount <= 0.0 || worldUBO.skyType != 1u || skyUBO.cameraSubmersionType != 3u) { return; }
    vec3 sunDir = normalize(skyUBO.sunDirection);
    bool day = sunDir.y > -0.02;
    vec3 lightDir = day ? sunDir : -sunDir;
    if (lightDir.y < -0.02) { return; }
    float rain = clamp(skyUBO.rainGradient, 0.0, 1.0);
    if (rain > 0.95) { return; }

    // Light position on screen.
    vec4 clip = worldUBO.cameraProjMat * (worldUBO.cameraEffectedViewMat * vec4(lightDir, 0.0));
    if (clip.w <= 1e-4) { return; }
    vec2 lightUv = clip.xy / clip.w * 0.5 + 0.5;
    // Fade as the light moves off screen (beams still reach in from just outside the edge).
    vec2 off = max(abs(lightUv - 0.5) - 0.5, vec2(0.0));
    float onScreen = 1.0 - smoothstep(0.0, 0.6, length(off));
    if (onScreen <= 0.0) { return; }

    ivec2 maskRes = imageSize(segmentationMaskImage);
    if (maskRes.x <= 0 || maskRes.y <= 0) { return; }
    vec2 uv = (vec2(pixel) + 0.5) / vec2(size);
    vec2 delta = (lightUv - uv);
    const int SAMPLES = 40;
    vec2 stepUv = delta / float(SAMPLES) * 0.9;
    vec2 p = uv + stepUv * shaftHash(vec2(pixel) + fract(worldUBO.gameTime * 1200.0) * 61.0);
    float decay = 1.0;
    float sum = 0.0;
    for (int i = 0; i < SAMPLES; ++i) {
        sum += shaftSky(p, maskRes) * decay;
        decay *= 0.965;
        p += stepUv;
    }
    sum /= float(SAMPLES) * 0.5;

    // Brighter near the light, warm and strong at golden hour, faint by moonlight.
    float dist = length((uv - lightUv) * vec2(float(size.x) / float(size.y), 1.0));
    float falloff = exp(-dist * 1.6);
    float e = lightDir.y;
    vec3 tint = day ? mix(vec3(1.0, 0.55, 0.25), vec3(1.0, 0.90, 0.75), smoothstep(0.02, 0.40, e))
                    : vec3(0.55, 0.62, 0.80) * 0.25;
    float golden = day ? mix(1.5, 0.8, smoothstep(0.05, 0.5, e)) : 1.0;
    float strength = sum * falloff * onScreen * golden * (1.0 - rain) * amount * 0.55;
    vec3 shafts = tint * strength;
    // Screen blend so beams never push bright areas past white.
    outColor = vec4(vec3(1.0) - (vec3(1.0) - clamp(scene.rgb, 0.0, 1.0)) * (vec3(1.0) - clamp(shafts, 0.0, 1.0)), scene.a);
}
