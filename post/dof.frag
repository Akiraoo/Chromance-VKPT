#version 460
#extension GL_GOOGLE_include_directive : require

// Depth of field for screenshots. Focus is either automatic (what the crosshair points at) or a fixed distance.
// Out-of-focus pixels gather a disc of samples whose size follows the circle of confusion; samples that are much
// closer to the camera and in focus are kept out, so a sharp foreground does not bleed into the blurred background.
// The hand and the sky-less void stay as they are.

#include "common/shared.hpp"

#ifndef CHR_POST_SCENE_BINDING
#    define CHR_POST_SCENE_BINDING 4
#endif
#ifndef CHR_DOF_AUTOFOCUS
#    define CHR_DOF_AUTOFOCUS 1
#endif
#ifndef CHR_DOF_FOCUS_DISTANCE
#    define CHR_DOF_FOCUS_DISTANCE 8.0
#endif
#ifndef CHR_DOF_STRENGTH
#    define CHR_DOF_STRENGTH 1.0
#endif

layout(set = 3, binding = 1) uniform sampler2D dofDepth;   // view-space depth of the first hit, in blocks
layout(set = 3, binding = 5, r8ui) readonly uniform uimage2D segmentationMaskImage;
layout(set = 4, binding = CHR_POST_SCENE_BINDING) uniform sampler2D dofScene;

layout(location = 0) out vec4 outColor;

float dofDepthAt(vec2 uv) {
    float d = texture(dofDepth, uv).r;
    return (d > 0.0 && d < 4096.0) ? d : 4096.0;
}

bool dofIsHand(vec2 uv) {
    ivec2 res = imageSize(segmentationMaskImage);
    if (res.x <= 0 || res.y <= 0) { return false; }
    ivec2 p = clamp(ivec2(uv * vec2(res)), ivec2(0), res - ivec2(1));
    return imageLoad(segmentationMaskImage, p).r == 0u;   // SEGMENT_SKIP: the first-person hand
}

void main() {
    ivec2 size = textureSize(dofScene, 0);
    ivec2 pixel = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    vec2 uv = (vec2(pixel) + 0.5) / vec2(size);
    vec4 scene = texelFetch(dofScene, pixel, 0);
    outColor = scene;
    if (dofIsHand(uv)) { return; }

    float focus = float(CHR_DOF_FOCUS_DISTANCE);
#if CHR_DOF_AUTOFOCUS
    // Focus on what the crosshair points at (a small cross of samples, nearest wins so thin things count).
    focus = dofDepthAt(vec2(0.5));
    focus = min(focus, dofDepthAt(vec2(0.5) + vec2(0.004, 0.0)));
    focus = min(focus, dofDepthAt(vec2(0.5) - vec2(0.004, 0.0)));
    focus = min(focus, dofDepthAt(vec2(0.5) + vec2(0.0, 0.007)));
    focus = min(focus, dofDepthAt(vec2(0.5) - vec2(0.0, 0.007)));
    focus = clamp(focus, 0.3, 1024.0);
#endif

    float depth = dofDepthAt(uv);
    float aperture = max(float(CHR_DOF_STRENGTH), 0.0);
    // Circle of confusion in pixels (thin lens, scaled to the screen height).
    float coc = abs(depth - focus) / max(depth, 1e-3) * (focus / (focus + 4.0)) * aperture * float(size.y) * 0.012;
    coc = clamp(coc, 0.0, 24.0);
    if (coc < 0.6) { return; }

    const int SAMPLES = 32;
    vec3 sum = scene.rgb;
    float wsum = 1.0;
    float golden = 2.3999632;
    for (int i = 1; i < SAMPLES; ++i) {
        float r = sqrt(float(i) / float(SAMPLES)) * coc;
        float a = float(i) * golden;
        vec2 suv = uv + vec2(cos(a), sin(a)) * r / vec2(size);
        float sd = dofDepthAt(suv);
        // A sample much nearer than this pixel only blurs in if it is itself out of focus.
        float sampleCoc = abs(sd - focus) / max(sd, 1e-3) * (focus / (focus + 4.0)) * aperture * float(size.y) * 0.012;
        float w = sd < depth - 0.5 ? clamp(sampleCoc / max(r, 1e-3), 0.0, 1.0) : 1.0;
        sum += texture(dofScene, suv).rgb * w;
        wsum += w;
    }
    outColor = vec4(sum / wsum, scene.a);
}
