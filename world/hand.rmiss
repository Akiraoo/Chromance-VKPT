#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require

// Miss for the first-person hand ray: nothing of the hand here.
#include "lib/payload.glsl"

#define INF_DISTANCE 65504.0

layout(location = 0) rayPayloadInEXT ChrRay ray;

void main() {
    ray.hitT = INF_DISTANCE;
    chrSetBit(ray, CHR_STOP_BIT, true);
}
