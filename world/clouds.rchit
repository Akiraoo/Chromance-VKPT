#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

// Block clouds, lit by the palette (no shadow rays: clouds sit above everything). Distant clouds melt into the
// sky colour instead of the regular distance fog, which would hide them completely.

#include "lib/resources_rt.glsl"
#include "lib/payload.glsl"
#include "interface/color_space.glsl"
#include "lib/palette.glsl"

layout(location = 0) rayPayloadInEXT ChrRay ray;
hitAttributeEXT vec2 attribs;

void main() {
    uint geometryBufferIndex = getGeometryBufferIndex(gl_InstanceCustomIndexEXT, gl_GeometryIndexEXT);
    uint i0, i1, i2;
    MaterialVertex m0, m1, m2;
    loadTriangleIndices(geometryBufferIndex, gl_PrimitiveID, i0, i1, i2);
    loadTriangleMaterial(geometryBufferIndex, i0, i1, i2, m0, m1, m2);
    vec3 bary = vec3(1.0 - attribs.x - attribs.y, attribs.x, attribs.y);
    uint packedData = m0.packedData;

    vec3 n = bary.x * m0.norm + bary.y * m1.norm + bary.z * m2.norm;
    n = getCoordinate(packedData) == 1u ? normalize(mat3(worldUBO.cameraViewMatInv) * n) : chrSafeNormalize(n, vec3(0.0, 1.0, 0.0));
    vec4 colorLayer = hasColorLayer(packedData) ? bary.x * m0.colorLayer + bary.y * m1.colorLayer + bary.z * m2.colorLayer : vec4(1.0);
    vec4 albedo = vec4(1.0);
    if (hasTexture(packedData)) {
        vec2 uv = bary.x * m0.textureUV + bary.y * m1.textureUV + bary.z * m2.textureUV;
        albedo = sampleTexture(textures[nonuniformEXT(m0.textureID)], uv, false);
    }
    vec3 tint = albedo.rgb * colorLayer.rgb;
    vec3 dir = normalize(gl_WorldRayDirectionEXT);

    ChrPalette pal = chrPalette();
    float ndotl = dot(n, pal.lightDir);
    float wrapped = clamp((ndotl + 0.45) / 1.45, 0.0, 1.0);
    float forward = pow(max(dot(dir, pal.lightDir), 0.0), 6.0);   // silver lining toward the sun
    vec3 sunLit = pal.lightColor * INV_PI * (0.30 + 0.70 * wrapped + forward * 0.8);
    vec3 skyLit = pal.zenith * 0.85 + pal.horizon * 0.35;
    vec3 color = tint * (sunLit + skyLit);

    float haze = smoothstep(96.0, 900.0, gl_HitTEXT) * 0.85;
    color = mix(color, textureLod(chrSkyCube, dir, 0.0).rgb, haze);

    ray.radiance += color * ray.throughput;
    ray.hitT = gl_HitTEXT;
    ray.normal = n;
    ray.directLight = color * ray.throughput;
    chrSetRayHasPrevScenePos(ray, false);
    ChrMaterial mat;
    mat.albedo = vec4(clamp(tint, vec3(0.0), vec3(1.0)), 1.0);
    mat.f0 = vec3(0.02);
    mat.roughness = 1.0;
    mat.metallic = 0.0;
    mat.transmission = 0.0;
    mat.ior = 1.0;
    mat.emission = 0.0;
    chrStoreMaterial(ray, mat);
    chrSetLobe(ray, CHR_LOBE_DIFFUSE);
    // The cloud's colour is computed exactly (no random sampling), so it skips the denoiser.
    chrSetBit(ray, CHR_NOISY_BIT, false);
    chrSetBit(ray, CHR_SKIP_FOG_BIT, true);
    chrSetBit(ray, CHR_STOP_BIT, true);
}
