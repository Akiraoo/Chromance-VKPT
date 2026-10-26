// Closest-hit shading for regular geometry (blocks, entities, the first-person hand).
// Included by surface.rchit and surface_flat.rchit. The hit shader shades the surface completely and samples the
// next direction; world.rgen only drives the loop.

#define CHR_NEED_PREVIOUS_GEOMETRY
#include "lib/resources_rt.glsl"
#include "lib/payload.glsl"
#include "lib/origin.glsl"
#include "interface/random.glsl"
#include "interface/ray_cone.glsl"
#include "interface/color_space.glsl"
#include "interface/vista_material.glsl"
#include "lib/brdf.glsl"
#include "lib/material.glsl"
#include "lib/texturing.glsl"
#include "lib/palette.glsl"
#include "lib/water.glsl"
#include "lib/rain.glsl"
#include "lib/rain_map.glsl"

layout(location = 0) rayPayloadInEXT ChrRay ray;
layout(location = 1) rayPayloadEXT ChrShadowRay shadowRay;
hitAttributeEXT vec2 attribs;

#include "lib/lights.glsl"

#ifndef CHR_FLAT_SURFACE
#    define CHR_FLAT_SURFACE 0
#endif

bool chrLoadPreviousScenePos(uint geometryBufferIndex, uint primitiveID, vec3 bary, out vec3 prevScenePos) {
    uint64_t lastPbrAddr = lastPbrBufferAddrs.addrs[geometryAddressIndex(geometryBufferIndex)];
    uint64_t lastIndexAddr = lastIndexBufferAddrs.addrs[geometryAddressIndex(geometryBufferIndex)];
    if (lastPbrAddr == 0 || lastIndexAddr == 0) { return false; }

    IndexBuffer lastIndexBuffer = IndexBuffer(lastIndexAddr);
    uint base = 3u * primitiveID;
    uint i0 = lastIndexBuffer.indices[base];
    uint i1 = lastIndexBuffer.indices[base + 1u];
    uint i2 = lastIndexBuffer.indices[base + 2u];

    vec3 p0, p1, p2;
    if (isChunkGeometryBufferIndex(geometryBufferIndex)) {
        ChunkPBRBuffer b = ChunkPBRBuffer(lastPbrAddr);
        p0 = vec3(b.vertices[i0].posX, b.vertices[i0].posY, b.vertices[i0].posZ);
        p1 = vec3(b.vertices[i1].posX, b.vertices[i1].posY, b.vertices[i1].posZ);
        p2 = vec3(b.vertices[i2].posX, b.vertices[i2].posY, b.vertices[i2].posZ);
    } else {
        EntityPBRBuffer b = EntityPBRBuffer(lastPbrAddr);
        p0 = b.vertices[i0].pos;
        p1 = b.vertices[i1].pos;
        p2 = b.vertices[i2].pos;
    }
    vec3 local = bary.x * p0 + bary.y * p1 + bary.z * p2;
    mat4 lastModel = lastObjToWorldMats.mat[gl_InstanceCustomIndexEXT];
    prevScenePos = mat3(lastModel) * local + lastModel[3].xyz;
    return true;
}

// Tangent-space normal map applied to a basis built from the texture derivatives. Keeps the result in front of
// the viewer so grazing angles do not turn black.
vec3 chrApplyNormalMap(vec3 tangentNormal, vec3 dPdu, vec3 dPdv, vec3 ng, vec3 v) {
    float strength = max(float(CHR_NORMAL_MAP_STRENGTH), 0.0);
    vec3 tn = vec3(tangentNormal.xy * strength, tangentNormal.z);
    tn.y = -tn.y;
    vec3 t = chrSafeNormalize(dPdu - ng * dot(ng, dPdu), abs(ng.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0));
    vec3 b = chrSafeNormalize(cross(ng, t), dPdv);
    t = cross(b, ng);
    vec3 n = chrSafeNormalize(t * tn.x + b * tn.y + ng * tn.z, ng);
    float NoV = dot(n, v);
    if (NoV < 0.05) { n = chrSafeNormalize(n + v * (0.05 - NoV), ng); }
    return n;
}

void main() {
    uint bounce = chrBounce(ray);
    bool cameraSegment = chrHasBit(ray, CHR_CAMERA_SEGMENT_BIT);

    uint geometryBufferIndex = getGeometryBufferIndex(gl_InstanceCustomIndexEXT, gl_GeometryIndexEXT);
    uint i0, i1, i2;
    PositionVertex p0, p1, p2;
    MaterialVertex m0, m1, m2;
    loadTriangle(geometryBufferIndex, gl_PrimitiveID, i0, i1, i2, p0, p1, p2, m0, m1, m2);

    vec3 bary = vec3(1.0 - attribs.x - attribs.y, attribs.x, attribs.y);
    float hitT = gl_HitTEXT;
    vec3 hitPos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * hitT;
    vec3 v = -gl_WorldRayDirectionEXT;

    uint packedData = m0.packedData;
    bool useTexture = hasTexture(packedData);
    vec4 colorLayer = hasColorLayer(packedData) ? bary.x * m0.colorLayer + bary.y * m1.colorLayer + bary.z * m2.colorLayer :
                                                 vec4(1.0);
    float albedoEmission = bary.x * m0.albedoEmission + bary.y * m1.albedoEmission + bary.z * m2.albedoEmission;
    uint alphaMode = getAlphaMode(packedData);

    mat3 objectToWorld = mat3(gl_ObjectToWorld3x4EXT);
    mat3 normalMatrix = transpose(mat3(gl_WorldToObject3x4EXT));
    vec3 ng = chrSafeNormalize(normalMatrix * cross(p1.pos - p0.pos, p2.pos - p0.pos), vec3(0.0, 1.0, 0.0));

    if (hasVistaMaterial(m0) && !hasWaterMaterial(m0) && worldUBO.vistaTextureID != 0u) {
        vec2 vistaUv = bary.x * m0.textureUV + bary.y * m1.textureUV + bary.z * m2.textureUV;
        vec3 objN = normalize(cross(p1.pos - p0.pos, p2.pos - p0.pos));
        float footprint = max(ray.coneWidth + hitT * ray.coneSpread, 0.0) / max(abs(dot(objN, gl_ObjectRayDirectionEXT)), 0.05);
        colorLayer.rgb = vistaAlbedo(textures[nonuniformEXT(worldUBO.vistaTextureID)], m0, vistaUv, colorLayer.rgb, footprint);
    }

    // ---- Textures ------------------------------------------------------------------------------------------
    bool isWater = hasWaterMaterial(m0);
    vec2 uv = vec2(0.0);
    vec2 uvMin = vec2(0.0);
    vec2 uvMax = vec2(0.0);
    float lod = 0.0;
    vec3 dPdu = objectToWorld * vec3(1.0, 0.0, 0.0);
    vec3 dPdv = objectToWorld * vec3(0.0, 1.0, 0.0);
    vec4 albedoTex = vec4(1.0);
    vec4 specularTex = CHR_DEFAULT_SPECULAR;
    vec4 normalTex = CHR_DEFAULT_NORMAL;
    bool bilinearPbr = CHR_PBR_FILTER != 0u;
    if (useTexture) {
        TextureMapEntry entry = mapping.entries[m0.textureID];
        uv = bary.x * m0.textureUV + bary.y * m1.textureUV + bary.z * m2.textureUV;
        uvMin = min(m0.textureUV, min(m1.textureUV, m2.textureUV));
        uvMax = max(m0.textureUV, max(m1.textureUV, m2.textureUV));
        vec3 dposdu, dposdv;
        computedposduDv(p0.pos, p1.pos, p2.pos, m0.textureUV, m1.textureUV, m2.textureUV, dposdu, dposdv);
        float coneRadius = ray.coneWidth + hitT * ray.coneSpread;
        lod = lodWithCone(textures[nonuniformEXT(m0.textureID)], uv, coneRadius, dposdu, dposdv);
        dPdu = objectToWorld * dposdu;
        dPdv = objectToWorld * dposdv;
        vec3 uvNormal = chrSafeNormalize(cross(dPdu, dPdv), ng);
        ng = uvNormal;

        albedoTex = resolveSurfaceTextureColor(sampleTexture(textures[nonuniformEXT(m0.textureID)], uv, lod, false), alphaMode);
        albedoTex.a = resolveSurfaceAlpha(albedoTex.a * colorLayer.a, alphaMode);
        if (entry.specular >= 0) {
            specularTex = chrSampleSpecular(textures[nonuniformEXT(entry.specular)], uv, uvMin, uvMax, lod, bilinearPbr);
        }
        if (entry.normal >= 0) {
            normalTex = chrSampleAtlas(textures[nonuniformEXT(entry.normal)], uv, uvMin, uvMax, lod, bilinearPbr);
        }
        if (entry.flag >= 0) {
            ivec4 flags = ivec4(round(sampleTexture(textures[nonuniformEXT(entry.flag)], uv, ceil(lod), false) * 255.0));
            isWater = isWater || (flags.r & 0x1) > 0;
        }
    } else {
        albedoTex.a = resolveSurfaceAlpha(colorLayer.a, alphaMode);
    }
    // Face the viewer.
    if (dot(ng, v) < 0.0) { ng = -ng; }

    vec3 glint = vec3(0.0);
    if (hasGlint(packedData)) {
        vec2 glintUV = bary.x * m0.glintUV + bary.y * m1.glintUV + bary.z * m2.glintUV;
        glintUV = (worldUBO.textureMat * vec4(glintUV, 0.0, 1.0)).xy;
        glint = sampleTexture(textures[nonuniformEXT(m0.glintTexture)], glintUV, false).rgb;
        glint *= glint;
    }
    vec3 tint = albedoTex.rgb * colorLayer.rgb;
    if (hasOverlay(packedData)) {
        vec4 overlay = sampleTexture(textures[nonuniformEXT(worldUBO.overlayTextureID)], m0.overlayUV, 0, false);
        tint = mix(overlay.rgb, tint, overlay.a);
    }
    tint += glint;

    ChrLabPbr m = chrDecodeLabPbr(vec4(tint, albedoTex.a), specularTex, normalTex);

    // Distant (Vista) terrain marks whole material classes as emissive, which made far grass glow at night.
    // Keep that glow only for lava-coloured surfaces.
    if (hasVistaMaterial(m0)) { albedoEmission *= step(tint.g * 1.6 + 0.02, tint.r); }

    // ---- Shading normal ------------------------------------------------------------------------------------
    vec3 n = ng;
    bool rippled = false;
    float distanceToCamera = length(hitPos - vec3(worldUBO.cameraEffectedViewMatInv[3]));
    if (isWater) {
        m.albedo = vec3(0.0);
        m.f0 = vec3(0.02);
        m.perceptualRoughness = 0.06;
        m.alpha = 0.0036;
        m.metallic = 0.0;
        m.subsurface = 0.0;
        m.transmission = 1.0;
        m.ior = CHR_WATER_IOR;
        m.ao = 1.0;
        // No glow from the water texture's specular map: a few of its texels carried an emission value, which made
        // them glow faintly and marked them "emissive" in the segmentation mask, so the wave and ripple overlays
        // skipped exactly those texels and the water showed its 16x16 pixel grid.
        m.emission = 0.0;
        albedoEmission = 0.0;
        if (abs(ng.y) > 0.7) {
            vec3 absPos = hitPos + chrWrappedCamera(worldUBO.cameraPos.xyz);
            vec3 waveN = chrWaterNormal(absPos.xz, worldUBO.gameTime, distanceToCamera);
            float rainHere = clamp(skyUBO.rainGradient, 0.0, 1.0);
            if (rainHere > 0.001 && ng.y > 0.0 && bounce == 0u) {
                float skyLightW = (bary.x * float(m0.lightUV.y) + bary.y * float(m1.lightUV.y) + bary.z * float(m2.lightUV.y)) / 16.0;
                ChrRainMap rainMapW = chrRainMap(hitPos, ng.y);
                float exposedW = (rainMapW.available ? rainMapW.exposure : smoothstep(12.5, 14.5, skyLightW)) * rainHere;
                // The water itself stays calm and transparent. Its rain ripples are drawn afterwards as an overlay
                // on the finished, denoised picture (post/rain_ripple.frag); this only marks the pixel for it.
                rippled = exposedW * float(CHR_RIPPLE_STRENGTH) > 0.02;
            }
            n = ng.y > 0.0 ? waveN : vec3(waveN.x, -waveN.y, waveN.z);
            if (dot(n, v) < 0.02) { n = ng; }
        }
    } else if (CHR_FLAT_SURFACE == 0 && useTexture && mapping.entries[m0.textureID].normal >= 0) {
        n = chrApplyNormalMap(m.tangentNormal, dPdu, dPdv, ng, v);
    }

    // Thin translucent surfaces (stained glass, ice, slime) do not bend light.
    bool thinTransmissive = !isWater && m.transmission > 0.0;
    vec3 glassTint = vec3(1.0);
    if (thinTransmissive) {
        // Stained glass, ice, slime: clear and tinted by the texture colour, with a faint sharp reflection.
        m.ior = 1.0;
        glassTint = mix(vec3(1.0), clamp(m.albedo * 1.1, vec3(0.0), vec3(1.0)), clamp(albedoTex.a * 1.4, 0.0, 1.0));
    }

    // ---- Rain: wet ground, puddles and ripples --------------------------------------------------------------
    // Only columns whose biome gets rain and that are open to the sky get wet (Radiance's rain map); deserts and
    // snowy places stay dry. The ground dries slowly after the rain; ripples follow the rain itself.
    float rainNow = clamp(skyUBO.rainGradient, 0.0, 1.0);
    ChrRainMap rainMap = chrRainMap(hitPos, ng.y);
    float rain = rainMap.available ? rainMap.wetness * rainMap.exposure : rainNow;
    if (!isWater && !thinTransmissive && worldUBO.skyType == 1u && rain > 0.001) {
        float skyLight = rainMap.available ? 15.0 :
                         (bary.x * float(m0.lightUV.y) + bary.y * float(m1.lightUV.y) + bary.z * float(m2.lightUV.y)) / 16.0;
        float rippleRain = rainMap.available ? rainNow * rainMap.exposure : rainNow;
        vec3 absPos = hitPos + chrWrappedCamera(worldUBO.cameraPos.xyz);
        ChrWetness w = chrRainWetness(absPos, ng, n, skyLight, rain, rippleRain, worldUBO.gameTime, bounce == 0u);
        if (w.wet > 0.0) {
            float porous = 1.0 - m.metallic;
            m.albedo *= mix(1.0, 0.6, w.wet * porous) * mix(1.0, 0.55, w.puddle * porous);
            // Wet surfaces get a water film: glossy even when the block itself has no labPBR smoothness.
            float rough = mix(m.perceptualRoughness, min(m.perceptualRoughness * 0.45, 0.32), w.wet);
            rough = mix(rough, 0.03, w.film);
            rough = mix(rough, 0.02, w.puddle);
            m.perceptualRoughness = rough;
            m.alpha = rough * rough;
            m.f0 = max(m.f0, vec3(mix(0.02, 0.05, max(w.puddle, w.film * 0.8))));
            n = w.normal;
            if (dot(n, v) < 0.02) { n = ng; }
            rippled = bounce == 0u && max(w.puddle, w.film) > 0.2 && float(CHR_RIPPLE_STRENGTH) > 0.0;
        }
    }

    // ---- Water volume the ray just crossed ------------------------------------------------------------------
    if (chrHasBit(ray, CHR_IN_WATER_BIT) && !cameraSegment) {
        vec3 transmittance = exp(-chrWaterAbsorptionTinted(chrRayWaterTint(ray)) * hitT);
        ChrPalette palWater = chrPalette();
        vec3 ambient = (palWater.zenith * 0.6 + palWater.lightColor * 0.05) * vec3(0.18, 0.42, 0.40);
        ray.radiance += ray.throughput * ambient * (1.0 - transmittance);
        ray.throughput *= transmittance;
    }

    // ---- Payload bookkeeping --------------------------------------------------------------------------------
    ray.hitT = hitT;
    ray.coneWidth += hitT * ray.coneSpread;
    ray.directLight = vec3(0.0);
    chrSetRayHasPrevScenePos(ray, false);
    if (bounce == 0u) {
        vec3 prev;
        if (chrLoadPreviousScenePos(geometryBufferIndex, gl_PrimitiveID, bary, prev)) {
            ray.prevScenePos = prev;
            chrSetRayHasPrevScenePos(ray, true);
        }
    }
    ray.normal = n;

    ChrMaterial stored;
    // Water: a flat, fully opaque albedo. The vanilla water texture's alpha varies from texel to texel; it ended up in
    // the denoiser's albedo guide, and DLSS Ray Reconstruction (which trusts the guide as texture) painted those
    // 16x16 texels back onto the calm water as a mosaic.
    stored.albedo = isWater ? vec4(0.95, 0.98, 1.0, 1.0) : vec4(m.albedo, albedoTex.a);
    stored.f0 = m.f0;
    stored.roughness = m.perceptualRoughness;
    stored.metallic = m.metallic;
    stored.transmission = m.transmission;
    stored.ior = m.ior;
    stored.emission = m.emission + albedoEmission;
    chrStoreMaterial(ray, stored);
    chrSetBit(ray, CHR_WATER_SURFACE_BIT, isWater);
    chrSetBit(ray, CHR_RIPPLE_BIT, rippled);
    chrSetBit(ray, CHR_TRANSMISSIVE_BIT, isWater || thinTransmissive);

    // ---- Emission -------------------------------------------------------------------------------------------
    float emission = m.emission + albedoEmission;
    if (emission > 0.0) {
        // The surface this ray came from already sampled block lights explicitly (for everything except
        // mirror-like reflection and refraction), so only sharp rays and camera rays may collect emission here.
        bool sharpRay = cameraSegment || chrHasBit(ray, CHR_SHARP_BIT);
        bool sampledByPrevious = !sharpRay && bounce > 0u && (bounce - 1u) < uint(CHR_BLOCK_LIGHT_BOUNCES);
        if (!sampledByPrevious) {
            ray.radiance += tint * emission * max(float(CHR_EMISSIVE_BRIGHTNESS), 0.0) * ray.throughput;
        }
    }

    // ---- Direct light ---------------------------------------------------------------------------------------
    ChrSurface s;
    s.albedo = m.albedo;
    s.f0 = m.f0;
    s.alpha = m.alpha;
    s.metallic = m.metallic;
    s.subsurface = m.subsurface;
    s.ao = m.ao;
    if (thinTransmissive) {
        // Glass gets no diffuse light; its reflection is picked up by the reflection ray.
        s.albedo = vec3(0.0);
        s.f0 = vec3(0.04);
        s.alpha = 0.0025;
        s.metallic = 0.0;
        s.subsurface = 0.0;
    }
    bool opaque = !(isWater || thinTransmissive);
    bool insideBoat = chrHasBit(ray, CHR_INSIDE_BOAT_BIT);

    ChrPalette pal = chrPalette();
    chrShadowWaterTint = chrRayWaterTint(ray);
    vec3 direct = chrSampleCelestialLight(pal, s, hitPos, n, ng, v, opaque, insideBoat, ray.seed);
    if (bounce < uint(CHR_BLOCK_LIGHT_BOUNCES) && !isWater) {
        // Several independent light samples on the surface the camera sees (less noise for the denoiser to
        // smear); one on deeper bounces.
        int lightSamples = bounce == 0u ? clamp(int(CHR_BLOCK_LIGHT_SAMPLES), 1, 8) : 1;
        vec3 blockLight = vec3(0.0);
        for (int i = 0; i < lightSamples; ++i) {
            blockLight += chrSampleBlockLight(s, hitPos, n, ng, v, opaque, insideBoat, ray.seed);
        }
        direct += blockLight / float(lightSamples);
    }
    direct *= ray.throughput;
    ray.radiance += direct;
    if (bounce == 0u) { ray.directLight = direct; }

    // ---- Next direction -------------------------------------------------------------------------------------
    vec3 nextDir;
    vec3 weight;
    uint lobe;
    vec3 originNormal = ng;
    float bias = 0.0003;
    if (isWater) {
        bool fromInside = chrHasBit(ray, CHR_IN_WATER_BIT);
        vec3 nn = dot(n, v) >= 0.0 ? n : -n;
        float eta = fromInside ? CHR_WATER_IOR : 1.0 / CHR_WATER_IOR;
        float cosI = clamp(dot(nn, v), 0.0, 1.0);
        float fresnel = chrDielectricFresnel(cosI, eta);
        vec3 refracted = refract(-v, nn, eta);
        bool canRefract = dot(refracted, refracted) > 1e-6;
        if (fromInside) {
            // Looking up from under water: always see through the surface (no total internal reflection). The
            // bending fades out towards the critical angle, so there is no hard ring where refraction stops.
            vec3 straight = -v;
            if (canRefract) {
                vec3 rd = normalize(refracted);
                float bendFade = smoothstep(0.0, 0.6, abs(dot(rd, nn)));
                nextDir = normalize(mix(straight, rd, bendFade));
            } else {
                nextDir = straight;
            }
            weight = vec3(1.0);
            lobe = CHR_LOBE_TRANSMISSION;
        } else {
            bool reflectIt = !canRefract || (bounce > 0u && rand(ray.seed) < fresnel);
            if (reflectIt) {
                nextDir = reflect(-v, nn);
                weight = vec3(1.0);
                lobe = CHR_LOBE_SPECULAR;
            } else {
                nextDir = normalize(refracted);
                // Deeper bounces pick reflection or refraction with probability F, so the weight is 1. At the
                // first hit world.rgen traces both branches and applies F and (1 - F) itself.
                weight = vec3(1.0);
                lobe = CHR_LOBE_TRANSMISSION;
            }
        }
        if (lobe == CHR_LOBE_TRANSMISSION) {
            chrSetBit(ray, CHR_IN_WATER_BIT, !fromInside);
            // Entering the water: remember its biome colour for the absorption along the way.
            if (!fromInside) {
                uint tint = chrPackWaterTint(colorLayer.rgb);
                if (tint != 0u) { chrSetRayWaterTint(ray, tint); }
            }
        }
        bias = CHR_WATER_ORIGIN_BIAS;
    } else if (thinTransmissive) {
        vec3 nn = dot(n, v) >= 0.0 ? n : -n;
        float fresnel = chrFresnelSchlick(vec3(0.04), clamp(dot(nn, v), 0.0, 1.0)).x;
        if (rand(ray.seed) < fresnel) {
            nextDir = reflect(-v, nn);
            weight = vec3(1.0);
            lobe = CHR_LOBE_SPECULAR;
        } else {
            nextDir = -v;
            weight = glassTint;
            lobe = CHR_LOBE_TRANSMISSION;
        }
    } else {
        vec2 u = vec2(rand(ray.seed), rand(ray.seed));
        if (!chrSampleBrdf(s, n, ng, v, u, rand(ray.seed), nextDir, weight, lobe)) {
            chrSetLobe(ray, CHR_LOBE_SPECULAR);
            chrSetBit(ray, CHR_NOISY_BIT, true);
            chrSetBit(ray, CHR_STOP_BIT, true);
            return;
        }
    }

    chrSetLobe(ray, lobe);
    chrSetBit(ray, CHR_NOISY_BIT, true);
    chrSetBit(ray, CHR_FROM_DIFFUSE_BIT, lobe == CHR_LOBE_DIFFUSE);
    chrSetBit(ray, CHR_SHARP_BIT, lobe == CHR_LOBE_TRANSMISSION || (lobe == CHR_LOBE_SPECULAR && (isWater || chrIsSharp(s))));
    chrSetBit(ray, CHR_CAMERA_SEGMENT_BIT, false);

    ray.throughput *= weight;
    if (max(ray.throughput.r, max(ray.throughput.g, ray.throughput.b)) <= 1e-5) {
        chrSetBit(ray, CHR_STOP_BIT, true);
        return;
    }
    ray.origin = chrOffsetOrigin(hitPos, originNormal, nextDir, bias);
    ray.direction = nextDir;
    chrSetBit(ray, CHR_STOP_BIT, false);
}
