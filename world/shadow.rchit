#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require

// A shadow ray that hits opaque geometry stays blocked (visible bit not set).
#include "lib/payload.glsl"

layout(location = 1) rayPayloadInEXT ChrShadowRay shadowRay;

void main() {}
