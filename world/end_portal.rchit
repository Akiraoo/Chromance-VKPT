#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

// End portal: animated starfield projected in screen space, as in vanilla.
#include "lib/resources_rt.glsl"
#include "lib/payload.glsl"
#include "interface/end_portal.glsl"

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
    vec4 texProj0 = projectPosition(worldUBO.cameraProjMat * worldUBO.cameraEffectedViewMat * vec4(worldPos, 1.0));
    vec3 color = computeEndPortalColor(texProj0, 16, worldUBO.endSkyTextureID, worldUBO.endPortalTextureID, worldUBO.gameTime);
    ray.radiance += 4.0 * color * ray.throughput;
    ray.hitT = gl_HitTEXT;
    ray.normal = vec3(0.0);
    ray.directLight = vec3(0.0);
    chrSetRayHasPrevScenePos(ray, false);
    chrClearMaterial(ray);
    chrSetBit(ray, CHR_NOISY_BIT, false);
    chrSetBit(ray, CHR_STOP_BIT, true);
}
