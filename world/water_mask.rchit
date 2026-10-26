#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

// Entering the inside of a boat: water there must not be drawn. Continue the ray from just behind the mask.
#include "lib/resources_rt.glsl"
#include "lib/payload.glsl"

layout(location = 0) rayPayloadInEXT ChrRay ray;
hitAttributeEXT vec2 attribs;

void main() {
    uint geometryBufferIndex = getGeometryBufferIndex(gl_InstanceCustomIndexEXT, gl_GeometryIndexEXT);
    uint i0, i1, i2;
    PositionVertex p0, p1, p2;
    loadTriangleIndices(geometryBufferIndex, gl_PrimitiveID, i0, i1, i2);
    loadTrianglePositions(geometryBufferIndex, i0, i1, i2, p0, p1, p2);
    vec3 bary = vec3(1.0 - attribs.x - attribs.y, attribs.x, attribs.y);
    vec3 local = bary.x * p0.pos + bary.y * p1.pos + bary.z * p2.pos;
    vec3 worldPos = vec4(local, 1.0) * gl_ObjectToWorld3x4EXT;
    ray.origin = worldPos + gl_WorldRayDirectionEXT * 0.001;
    chrSetBit(ray, CHR_INSIDE_BOAT_BIT, true);
    chrSetBit(ray, CHR_CONTINUE_BIT, true);
    ray.hitT = gl_HitTEXT;
    ray.coneWidth += gl_HitTEXT * ray.coneSpread;
}
