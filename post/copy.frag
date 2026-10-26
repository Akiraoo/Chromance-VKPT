#version 460

// Copies out:ldr pixel for pixel into post_scene_color so the grade pass can read the frame it overwrites.
layout(set = 3, binding = 0) uniform sampler2D postCopyInput;

layout(location = 0) out vec4 outColor;

void main() {
    ivec2 size = textureSize(postCopyInput, 0);
    ivec2 pixel = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    outColor = texelFetch(postCopyInput, pixel, 0);
}
