#version 460
#extension GL_GOOGLE_include_directive : require

// Renders the time-of-day sky gradient into a small cube map once per frame. Every ray that leaves the world
// reads its sky colour from here.

#include "common/shared.hpp"
#include "lib/settings.glsl"

layout(set = 2, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};

layout(set = 2, binding = 2) uniform SkyUniform {
    SkyUBO skyUBO;
};

#include "lib/palette.glsl"

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 outColor;

void main() {
    vec2 c = texCoord * 2.0 - 1.0;
    vec3 dir = normalize(vec3(-c.x, -c.y, -1.0));
    if (FACE == 0) {
        dir = normalize(vec3(1.0, -c.y, -c.x));
    } else if (FACE == 1) {
        dir = normalize(vec3(-1.0, -c.y, c.x));
    } else if (FACE == 2) {
        dir = normalize(vec3(c.x, 1.0, c.y));
    } else if (FACE == 3) {
        dir = normalize(vec3(c.x, -1.0, -c.y));
    } else if (FACE == 4) {
        dir = normalize(vec3(c.x, -c.y, 1.0));
    }
    ChrPalette pal = chrPalette();
    outColor = vec4(chrSkyRadiance(pal, dir), 1.0);
}
