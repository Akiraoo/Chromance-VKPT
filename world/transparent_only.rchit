#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

// Lightning bolts and beacon beams: glowing, see-through, no shading. The ray continues behind them.
#include "lib/resources_rt.glsl"
#include "lib/payload.glsl"
#include "interface/color_space.glsl"
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
    vec4 colorLayer = hasColorLayer(m0.packedData) ? bary.x * m0.colorLayer + bary.y * m1.colorLayer + bary.z * m2.colorLayer : vec4(1.0);

    vec4 albedo = vec4(1.0);
    float emission = 1.0;
    if (hasTexture(m0.packedData)) {
        vec2 uv = bary.x * m0.textureUV + bary.y * m1.textureUV + bary.z * m2.textureUV;
        albedo = resolveSurfaceTextureColor(sampleTexture(textures[nonuniformEXT(m0.textureID)], uv, 0.0, false), getAlphaMode(m0.packedData));
        int specular = mapping.entries[m0.textureID].specular;
        if (specular >= 0) {
            vec2 uvMin = min(m0.textureUV, min(m1.textureUV, m2.textureUV));
            vec2 uvMax = max(m0.textureUV, max(m1.textureUV, m2.textureUV));
            int id = int(round(chrSampleSpecular(textures[nonuniformEXT(specular)], uv, uvMin, uvMax, 0.0, false).a * 255.0));
            if (id < 255) { emission = max(float(id) / 254.0, 0.0); }
        }
    }
    vec4 shaded = albedo * colorLayer;
    float alpha = clamp(shaded.a, 0.0, 1.0);
    vec3 rgb = clamp(shaded.rgb, vec3(0.0), vec3(1.0));
    ray.radiance += rgb * alpha * emission * 3.0 * max(float(CHR_EMISSIVE_BRIGHTNESS), 0.0) * ray.throughput;
    ray.throughput *= vec3(1.0 - alpha * 0.5);

    vec3 worldPos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;
    vec3 n = normalize(transpose(mat3(gl_WorldToObject3x4EXT)) * cross(p1.pos - p0.pos, p2.pos - p0.pos));
    if (dot(n, -gl_WorldRayDirectionEXT) < 0.0) { n = -n; }
    ray.normal = n;
    ChrMaterial mat;
    mat.albedo = vec4(rgb, alpha);
    mat.f0 = vec3(0.02);
    mat.roughness = 1.0;
    mat.metallic = 0.0;
    mat.transmission = 1.0;
    mat.ior = 1.0;
    mat.emission = emission;
    chrStoreMaterial(ray, mat);
    chrSetLobe(ray, CHR_LOBE_DIFFUSE);
    chrSetBit(ray, CHR_NOISY_BIT, false);
    ray.directLight = vec3(0.0);
    chrSetRayHasPrevScenePos(ray, false);
    ray.origin = worldPos + gl_WorldRayDirectionEXT * 0.001;
    ray.hitT = gl_HitTEXT;
    ray.coneWidth += gl_HitTEXT * ray.coneSpread;
    chrSetBit(ray, CHR_CONTINUE_BIT, true);
    chrSetBit(ray, CHR_STOP_BIT, false);
}
