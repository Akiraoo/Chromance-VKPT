#version 460
#extension GL_GOOGLE_include_directive : require

// Renders the cloud shadow map (see lib/clouds.glsl) once per frame, before the world is traced.

#include "common/shared.hpp"
#include "lib/settings.glsl"

layout(set = 2, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};

layout(set = 2, binding = 2) uniform SkyUniform {
    SkyUBO skyUBO;
};

#include "lib/palette.glsl"
#include "lib/clouds.glsl"

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 outColor;

void main() {
    ChrPalette pal = chrPalette();
    vec2 midXZ = chrCloudShadowCentre() + (texCoord - 0.5) * CHR_CLOUD_SHADOW_RANGE;
    outColor = vec4(chrCloudShadowRay(midXZ, pal.lightDir), 0.0, 0.0, 1.0);
}
