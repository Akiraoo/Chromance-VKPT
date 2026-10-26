#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require

// A shadow ray that reaches nothing means the light is visible.
#include "lib/payload.glsl"

layout(location = 1) rayPayloadInEXT ChrShadowRay shadowRay;

void main() {
    shadowRay.visible |= 1u;
}
