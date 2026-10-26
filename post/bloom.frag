#version 460
#extension GL_GOOGLE_include_directive : require

// Bloom, one step of a downsampling chain. The first step reads the HDR frame (before tone mapping) and keeps only
// what is brighter than CHR_BLOOM_THRESHOLD (with a soft knee), so only lights, the sun and bright reflections
// glow, not every bright wall. Each step blurs with a 13-tap filter while halving the size; post/grade.frag adds
// the three levels back on top of the picture.

#include "common/shared.hpp"

#ifndef CHR_BLOOM_THRESHOLD
#    define CHR_BLOOM_THRESHOLD 1.4
#endif
#ifndef CHR_BLOOM_SOURCE_BINDING
#    define CHR_BLOOM_SOURCE_BINDING 13
#endif

layout(set = 3, binding = 2) uniform sampler2D bloomHdr;   // HDR frame, display size
#ifndef CHR_BLOOM_FIRST
layout(set = 4, binding = CHR_BLOOM_SOURCE_BINDING) uniform sampler2D bloomSource;
#endif

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 outColor;

vec3 bloomFetch(vec2 uv) {
#ifdef CHR_BLOOM_FIRST
    vec3 c = max(texture(bloomHdr, uv).rgb, vec3(0.0));
    if (any(isnan(c)) || any(isinf(c))) { c = vec3(0.0); }
    float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
    float t = float(CHR_BLOOM_THRESHOLD);
    float knee = t * 0.5;
    float soft = clamp(lum - t + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1e-4);
    float contribution = max(soft, lum - t) / max(lum, 1e-4);
    // Keep extreme values (the sun's core) from dominating.
    return min(c * contribution, vec3(16.0));
#else
    return texture(bloomSource, uv).rgb;
#endif
}

void main() {
#ifdef CHR_BLOOM_FIRST
    vec2 texel = 1.0 / vec2(textureSize(bloomHdr, 0)) * 2.0;
#else
    vec2 texel = 1.0 / vec2(textureSize(bloomSource, 0));
#endif
    vec2 uv = texCoord;
    // 13-tap downsample (Call of Duty: Advanced Warfare style): soft and free of flicker.
    vec3 a = bloomFetch(uv + texel * vec2(-1.0, -1.0));
    vec3 b = bloomFetch(uv + texel * vec2(0.0, -1.0));
    vec3 c = bloomFetch(uv + texel * vec2(1.0, -1.0));
    vec3 d = bloomFetch(uv + texel * vec2(-0.5, -0.5));
    vec3 e = bloomFetch(uv + texel * vec2(0.5, -0.5));
    vec3 f = bloomFetch(uv + texel * vec2(-1.0, 0.0));
    vec3 g = bloomFetch(uv);
    vec3 h = bloomFetch(uv + texel * vec2(1.0, 0.0));
    vec3 i = bloomFetch(uv + texel * vec2(-0.5, 0.5));
    vec3 j = bloomFetch(uv + texel * vec2(0.5, 0.5));
    vec3 k = bloomFetch(uv + texel * vec2(-1.0, 1.0));
    vec3 l = bloomFetch(uv + texel * vec2(0.0, 1.0));
    vec3 m = bloomFetch(uv + texel * vec2(1.0, 1.0));
    vec3 result = (d + e + i + j) * 0.125 + (a + c + k + m) * 0.03125 + (b + f + h + l) * 0.0625 + g * 0.125;
    outColor = vec4(result, 1.0);
}
