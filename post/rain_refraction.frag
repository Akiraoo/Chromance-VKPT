#version 460
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_GOOGLE_include_directive : require

// Rain streaks as clear water: each streak bends the picture behind it like a thin glass rod and only catches a
// little light at its edges, instead of being painted on as a blue stripe. Reads the frame copied just before
// the weather pass (post_scene_color) and writes the result without blending.

#include "common/shared.hpp"
#include "lib/origin.glsl"

#ifndef CHR_POST_SCENE_BINDING
#    define CHR_POST_SCENE_BINDING 4
#endif
#ifndef CHR_RAIN_AMOUNT
#    define CHR_RAIN_AMOUNT 0.45
#endif
#ifndef CHR_RAIN_OPACITY
#    define CHR_RAIN_OPACITY 0.4
#endif

layout(set = 0, binding = 0) uniform sampler2D textures[];

layout(set = 1, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};

layout(set = 4, binding = CHR_POST_SCENE_BINDING) uniform sampler2D rainScene;

layout(location = 0) in vec3 pos;
layout(location = 3) flat in uint useColorLayer;
layout(location = 4) in vec4 colorLayer;
layout(location = 5) flat in uint useTexture;
layout(location = 7) in vec2 textureUV;
layout(location = 10) flat in uint textureID;

layout(location = 0) out vec4 fragColor;

float rainHash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    if (useTexture == 0u) { discard; }
    vec4 streak = texture(textures[nonuniformEXT(textureID)], textureUV);
    if (useColorLayer > 0u) { streak *= colorLayer; }
    if (streak.a < 0.1) { discard; }

#ifndef CHR_RAIN_PARTICLE
    // Keep or drop whole streak columns with a stable hash so the remaining drops do not flicker.
    vec2 column = chrWrappedColumn(pos.xz, worldUBO.cameraPos.xz);
    if (rainHash(column) > float(CHR_RAIN_AMOUNT)) { discard; }
#endif

    ivec2 size = textureSize(rainScene, 0);
    if (size.x <= 0 || size.y <= 0) { discard; }
    ivec2 pixel = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));

    // Each texel column of the rain texture is treated as a small cylinder.
    ivec2 texSize = textureSize(textures[nonuniformEXT(textureID)], 0);
    float lensX = texSize.x > 0 ? fract(textureUV.x * float(texSize.x)) : textureUV.x;
    float cx = clamp(lensX * 2.0 - 1.0, -0.98, 0.98);
    float cz = sqrt(max(1.0 - cx * cx, 1e-4));
    float bend = clamp(cx / max(cz, 0.2), -4.0, 4.0) / 4.0;
    float coverage = smoothstep(0.05, 0.5, streak.a);

    float linearDepth = max(-(mat4(mat3(worldUBO.cameraEffectedViewMat)) * vec4(pos, 1.0)).z, 0.0);
    // Near drops bend more, far ones barely.
    float strength = clamp(float(CHR_RAIN_OPACITY), 0.0, 1.0);
    float maxOffset = float(size.x) * 0.018 * strength / (1.0 + linearDepth * 0.15);
    ivec2 refractedPixel = clamp(pixel + ivec2(int(round(bend * coverage * maxOffset)), 0), ivec2(0), size - ivec2(1));

    vec3 base = texelFetch(rainScene, pixel, 0).rgb;
    vec3 refracted = texelFetch(rainScene, refractedPixel, 0).rgb;
    float edge = pow(abs(cx), 3.0) * coverage;
    vec3 highlight = max(base, refracted) * (0.10 + 0.25 * edge) * strength + vec3(0.015) * edge * strength;
    vec3 color = mix(base, refracted, coverage) + highlight * coverage;

    fragColor = vec4(clamp(color, vec3(0.0), vec3(1.0)), 1.0);
    gl_FragDepth = clamp(linearDepth / 1000.0, 0.0, 1.0);
}
