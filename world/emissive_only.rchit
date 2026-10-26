#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

// Glowing overlays (spider and enderman eyes and similar): emission only, no lighting, no bounce.
#include "lib/resources_rt.glsl"
#include "lib/payload.glsl"
#include "interface/ray_cone.glsl"
#include "interface/color_space.glsl"
#include "lib/material.glsl"
#include "lib/texturing.glsl"

layout(location = 0) rayPayloadInEXT ChrRay ray;
hitAttributeEXT vec2 attribs;

void main() {
    uint geometryBufferIndex = getGeometryBufferIndex(gl_InstanceCustomIndexEXT, gl_GeometryIndexEXT);
    uint i0, i1, i2;
    PositionVertex p0, p1, p2;
    MaterialVertex m0, m1, m2;
    loadTriangle(geometryBufferIndex, gl_PrimitiveID, i0, i1, i2, p0, p1, p2, m0, m1, m2);
    vec3 bary = vec3(1.0 - attribs.x - attribs.y, attribs.x, attribs.y);
    uint packedData = m0.packedData;
    uint alphaMode = getAlphaMode(packedData);
    vec4 colorLayer = hasColorLayer(packedData) ? bary.x * m0.colorLayer + bary.y * m1.colorLayer + bary.z * m2.colorLayer : vec4(1.0);

    vec4 albedo = vec4(1.0);
    vec4 specular = CHR_DEFAULT_SPECULAR;
    if (hasTexture(packedData)) {
        vec2 uv = bary.x * m0.textureUV + bary.y * m1.textureUV + bary.z * m2.textureUV;
        vec2 uvMin = min(m0.textureUV, min(m1.textureUV, m2.textureUV));
        vec2 uvMax = max(m0.textureUV, max(m1.textureUV, m2.textureUV));
        vec3 dposdu, dposdv;
        computedposduDv(p0.pos, p1.pos, p2.pos, m0.textureUV, m1.textureUV, m2.textureUV, dposdu, dposdv);
        float lod = lodWithCone(textures[nonuniformEXT(m0.textureID)], uv, ray.coneWidth + gl_HitTEXT * ray.coneSpread, dposdu, dposdv);
        albedo = resolveSurfaceTextureColor(sampleTexture(textures[nonuniformEXT(m0.textureID)], uv, lod, false), alphaMode);
        int specularId = mapping.entries[m0.textureID].specular;
        if (specularId >= 0) { specular = chrSampleSpecular(textures[nonuniformEXT(specularId)], uv, uvMin, uvMax, lod, false); }
    }
    vec3 tint = albedo.rgb * colorLayer.rgb;
    ChrLabPbr m = chrDecodeLabPbr(vec4(tint, albedo.a), specular, CHR_DEFAULT_NORMAL);
    // These layers are meant to glow even without labPBR data.
    // Kept modest: a faint glow, not LEDs.
    float glow = max(m.emission, 0.6);
    ray.radiance += tint * glow * 0.12 * max(float(CHR_EMISSIVE_BRIGHTNESS), 0.0) * ray.throughput;
    ray.hitT = gl_HitTEXT;
    ray.normal = vec3(0.0);
    ray.directLight = vec3(0.0);
    chrSetRayHasPrevScenePos(ray, false);
    ChrMaterial mat;
    mat.albedo = vec4(clamp(tint, vec3(0.0), vec3(1.0)), albedo.a);
    mat.f0 = m.f0;
    mat.roughness = m.perceptualRoughness;
    mat.metallic = m.metallic;
    mat.transmission = 0.0;
    mat.ior = 1.5;
    mat.emission = glow;
    chrStoreMaterial(ray, mat);
    chrSetBit(ray, CHR_NOISY_BIT, false);
    chrSetBit(ray, CHR_STOP_BIT, true);
}
