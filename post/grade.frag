#version 460
#extension GL_GOOGLE_include_directive : require

// Final colour grade on the tone-mapped image: contrast curve per channel, saturation and vibrance, a vignette
// that darkens dark corners more than bright ones, and optional film grain. Reads the copy of the frame made by
// the previous pass and writes out:ldr.

#include "common/shared.hpp"

#ifndef CHR_POST_SCENE_BINDING
#    define CHR_POST_SCENE_BINDING 4
#endif
#ifndef CHR_GRADE_ENABLED
#    define CHR_GRADE_ENABLED 1
#endif
#ifndef CHR_GRADE_CONTRAST
#    define CHR_GRADE_CONTRAST 1.1
#endif
#ifndef CHR_GRADE_SATURATION
#    define CHR_GRADE_SATURATION 1.08
#endif
#ifndef CHR_GRADE_VIBRANCE
#    define CHR_GRADE_VIBRANCE 1.15
#endif
#ifndef CHR_GRADE_VIGNETTE
#    define CHR_GRADE_VIGNETTE 0.6
#endif
#ifndef CHR_GRADE_WARMTH
#    define CHR_GRADE_WARMTH 0.6
#endif
#ifndef CHR_GRADE_PUNCH
#    define CHR_GRADE_PUNCH 0.5
#endif
#ifndef CHR_BLOOM_ENABLED
#    define CHR_BLOOM_ENABLED 0
#endif
#ifndef CHR_BLOOM_STRENGTH
#    define CHR_BLOOM_STRENGTH 0.5
#endif
#ifndef CHR_GRADE_FILM_GRAIN
#    define CHR_GRADE_FILM_GRAIN 0.0
#endif

layout(set = 1, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};

layout(set = 1, binding = 1) uniform SkyUniform {
    SkyUBO skyUBO;
};

// "post_scene_color" is a texture name Radiance recognises: it is backed by a full-resolution copy of out:ldr.
layout(set = 4, binding = CHR_POST_SCENE_BINDING) uniform sampler2D gradeScene;

#if CHR_BLOOM_ENABLED
layout(set = 4, binding = 13) uniform sampler2D bloomA;
layout(set = 4, binding = 14) uniform sampler2D bloomB;
layout(set = 4, binding = 15) uniform sampler2D bloomC;
#endif

layout(set = 3, binding = 5, r8ui) readonly uniform uimage2D gradeSegmentation;

// Eye adaptation state (exposure/adapt.comp); .w = night vision strength.
layout(set = 4, binding = 10) uniform sampler2D gradeEyeState;
// world.rgen's camera state: x = how much sky the camera has above it (eased), z = 1 once written.
layout(set = 4, binding = 17) uniform sampler2D gradeCameraState;

layout(location = 0) out vec4 outColor;

const vec3 GRADE_LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 gradeToLinear(vec3 c) {
    c = clamp(c, vec3(0.0), vec3(1.0));
    return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThanEqual(c, vec3(0.04045)));
}

vec3 gradeToSrgb(vec3 c) {
    c = max(c, vec3(0.0));
    return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThanEqual(c, vec3(0.0031308)));
}

// S-curve around mid grey in perceptual space. contrast = 1 leaves the image untouched; white and black stay put.
vec3 gradeContrast(vec3 srgb, float contrast) {
    vec3 x = clamp(srgb, vec3(0.0), vec3(1.0));
    vec3 lifted = x * x * (3.0 - 2.0 * x);   // smoothstep curve
    float amount = clamp(contrast - 1.0, -1.0, 1.0);
    return amount >= 0.0 ? mix(x, lifted, amount) : mix(x, vec3(0.5) + (x - 0.5) * 0.6, -amount);
}

vec3 gradeSaturation(vec3 linearColor, float rain) {
    float luma = dot(linearColor, GRADE_LUMA);
    float chroma = max(linearColor.r, max(linearColor.g, linearColor.b)) - min(linearColor.r, min(linearColor.g, linearColor.b));
    float vibrance = (float(CHR_GRADE_VIBRANCE) - 1.0) * (1.0 - clamp(chroma * 2.0, 0.0, 1.0)) * (1.0 - rain);
    float amount = max(float(CHR_GRADE_SATURATION) + vibrance, 0.0) * mix(1.0, 0.62, rain);
    return max(mix(vec3(luma), linearColor, amount), vec3(0.0));
}

float gradeNoise(uvec2 p, uint seed) {
    uint s = p.x * 1973u + p.y * 9277u + seed * 26699u;
    s = (s ^ 61u) ^ (s >> 16u);
    s *= 9u;
    s ^= s >> 4u;
    s *= 0x27d4eb2du;
    s ^= s >> 15u;
    return float(s) * (1.0 / 4294967295.0);
}

void main() {
    ivec2 size = textureSize(gradeScene, 0);
    ivec2 pixel = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    vec4 scene = texelFetch(gradeScene, pixel, 0);
#if CHR_GRADE_ENABLED
    vec2 uv = (vec2(pixel) + 0.5) / vec2(size);

    // Deband: Radiance converts the picture to 8 bits per channel before the pack sees it, so smooth gradients
    // (rainy sky, fog, dusk) arrive as wide steps. Look at 8 pixels at random distances up to 64 pixels away and
    // average the ones that are within a couple of 8-bit steps of this pixel: inside a gradient that melts the steps
    // into a smooth ramp, while real detail (and rain streaks) differs by more and is left out of the average.
    // Water is skipped: its faint rain rings and wave bands are only a step or two apart in 8 bits, and averaging
    // them away in some places but not others left blotchy squares on the water.
    ivec2 segSize = imageSize(gradeSegmentation);
    ivec2 segPixel = clamp(ivec2(uv * vec2(segSize)), ivec2(0), max(segSize - ivec2(1), ivec2(0)));
    bool gradeWater = segSize.x > 0 && (imageLoad(gradeSegmentation, segPixel).r & 48u) != 0u;
    if (!gradeWater) {
        vec3 c = scene.rgb;
        vec3 sum = c;
        float count = 1.0;
        // Only differences of a single 8-bit step count as banding; dark cloud edges at night differ by more.
        const float threshold = 1.5 / 255.0;
        float baseAngle = gradeNoise(uvec2(pixel), 0x68e31da4u) * 6.2831853;
        for (int i = 0; i < 8; ++i) {
            float angle = baseAngle + float(i) * 2.3999632;   // golden angle: spread the directions
            float radius = mix(6.0, 40.0, gradeNoise(uvec2(pixel) + uvec2(uint(i) * 17u, 3u), 0xb5297a4du));
            ivec2 q = clamp(pixel + ivec2(vec2(cos(angle), sin(angle)) * radius), ivec2(0), size - ivec2(1));
            vec3 sc = texelFetch(gradeScene, q, 0).rgb;
            if (all(lessThan(abs(sc - c), vec3(threshold)))) {
                sum += sc;
                count += 1.0;
            }
        }
        // Require most samples to agree, so edges (where only some neighbours match) are left sharp.
        if (count >= 7.0) { scene.rgb = sum / count; }
    }

#if CHR_BLOOM_ENABLED
    {
        // Bloom: the three blurred levels of the bright parts, widest last, added in linear light and gently
        // compressed so they glow rather than clip.
        vec3 bloom = texture(bloomA, uv).rgb * 0.45 + texture(bloomB, uv).rgb * 0.35 + texture(bloomC, uv).rgb * 0.30;
        bloom = bloom / (1.0 + bloom);
        vec3 lin = gradeToLinear(scene.rgb) + bloom * max(float(CHR_BLOOM_STRENGTH), 0.0) * 0.5;
        scene.rgb = gradeToSrgb(lin);
    }
#endif
    // Night vision, part two: a mild gamma lift of the finished picture on top of the even light added in world.rgen.
    // Kept small: a strong lift also lifts the denoiser's leftover noise in the dark.
    {
        float nightVision = clamp(texelFetch(gradeEyeState, ivec2(0), 0).w, 0.0, 1.0);
        if (nightVision > 0.001) {
            scene.rgb = pow(clamp(scene.rgb, vec3(0.0), vec3(1.0)), vec3(1.0 / (1.0 + 0.5 * nightVision)));
        }
    }
    // The rainy-day look (paler, cooler, flatter) only where the camera is out under the sky: deep in a cave it
    // is not raining, and the cave should keep its own colours.
    vec4 cameraState = texelFetch(gradeCameraState, ivec2(0), 0);
    float skyAccess = cameraState.z > 0.5 ? clamp(cameraState.x, 0.0, 1.0) : 1.0;
    float rain = clamp(skyUBO.rainGradient, 0.0, 1.0) * (skyUBO.cameraSubmersionType == 3u ? 1.0 : 0.0) *
                 smoothstep(0.0, 0.6, skyAccess);
    vec3 color = gradeContrast(scene.rgb, float(CHR_GRADE_CONTRAST));
    vec3 linearColor = gradeSaturation(gradeToLinear(color), rain);
    linearColor *= mix(vec3(1.0), vec3(0.80, 0.86, 0.95), rain);


    // Cinematic split tone: cool shadows, warm highlights (sunlit surfaces glow, shade reads blue), stronger in
    // fair weather.
    {
        float warmth = clamp(float(CHR_GRADE_WARMTH), 0.0, 1.0) * (1.0 - rain * 0.7);
        float lum = dot(linearColor, GRADE_LUMA);
        vec3 shadowTint = mix(vec3(1.0), vec3(0.93, 0.99, 1.08), warmth);
        vec3 highlightTint = mix(vec3(1.0), vec3(1.08, 1.0, 0.88), warmth);
        linearColor *= mix(shadowTint, highlightTint, smoothstep(0.015, 0.45, lum));
    }
    color = gradeToSrgb(linearColor);

    // Punch: a filmic S-curve and a touch more colour on top of the contrast setting.
    {
        float punch = clamp(float(CHR_GRADE_PUNCH), 0.0, 1.0);
        vec3 x = clamp(color, vec3(0.0), vec3(1.0));
        vec3 s = x * x * (3.0 - 2.0 * x);
        color = mix(x, s, punch * 0.45);
        float l = dot(color, GRADE_LUMA);
        color = max(mix(vec3(l), color, 1.0 + punch * 0.18), vec3(0.0));
    }

    vec2 centered = uv - 0.5;
    float edge = dot(centered, centered);
    float darkness = 1.0 - clamp(dot(color, GRADE_LUMA), 0.0, 1.0);
    color *= max(1.0 - edge * (0.9 + 0.3 * darkness) * float(CHR_GRADE_VIGNETTE), 0.0);

    float grain = gradeNoise(uvec2(pixel), worldUBO.seed) - 0.5;
    color += vec3(grain * float(CHR_GRADE_FILM_GRAIN) / 96.0);
    // Triangular dither of one 8-bit step: breaks up the banding in smooth sky gradients.
    float dither = gradeNoise(uvec2(pixel), worldUBO.seed ^ 0x5bd1e995u) + gradeNoise(uvec2(pixel) + uvec2(7u, 13u), worldUBO.seed) - 1.0;
    color += vec3(dither * 1.5 / 255.0);
    outColor = vec4(clamp(color, vec3(0.0), vec3(1.0)), scene.a);
#else
    outColor = scene;
#endif
}
