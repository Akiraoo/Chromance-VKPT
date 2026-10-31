#ifndef CHR_LIGHTS_GLSL
#define CHR_LIGHTS_GLSL

// Direct lighting: sun / moon and block lights.
//
// Block lights are sampled explicitly from the emissive triangles Radiance collects per chunk section
// (requires_emission). Every diffuse bounce picks one light out of a few candidates (resampled importance
// sampling) and traces one shadow ray toward it. Compared with waiting for random bounce rays to stumble onto a
// torch flame, this keeps torch light stable while the camera moves, which is what removes the flicker.
// Light is faded out over CHR_BLOCK_LIGHT_RANGE blocks so a torch lights a small area and the rest stays dark.
//
// Requires lib/resources_rt.glsl, lib/payload.glsl, lib/brdf.glsl, lib/palette.glsl, interface/random.glsl and a
// `layout(location = 1) rayPayloadEXT ChrShadowRay shadowRay;` declaration.

#define CHR_CLOUD_SHADOW_LOOKUP
#include "lib/clouds.glsl"

struct ChrChunkLights {
    int originX;
    int originY;
    int originZ;
    uint geometryCount;
    uint staticLightCount;
    uint64_t staticLightAddress;
    uint entityLightCount;
    uint64_t entityLightAddress;
    uint globalEntityLightCount;
    uint64_t globalEntityLightAddress;
};

struct ChrPackedLight {
    vec4 p0Area;
    vec4 p1;
    vec4 p2;
    vec4 p3;
    vec4 normal;
    vec4 radiance;   // rgb = colour * emission, a = small-light boost from Radiance
    vec4 sourceId;
};

layout(std430, set = 1, binding = 9) readonly buffer ChrChunkLightBuffer {
    ChrChunkLights chrChunkLights[];
};

layout(std430, buffer_reference, buffer_reference_align = 16) readonly buffer ChrPackedLightBuffer {
    ChrPackedLight lights[];
};

const uint CHR_MAX_LIGHTS_PER_SECTION = 65536u;

int chrFloorMod(int a, int b) {
    return a - b * int(floor(float(a) / float(b)));
}

// Index of a chunk section in Radiance's ring-buffer grid.
bool chrSectionIndex(ivec3 section, out uint index) {
    index = 0u;
    ivec4 grid = worldUBO.chunkGridInfo;
    if (grid.x <= 0 || grid.y <= 0 || grid.z <= 0) { return false; }
    ivec3 storage = worldUBO.chunkStorageSectionPos.xyz;
    int viewDistance = (grid.x - 1) / 2;
    if (section.y < grid.w || section.y >= grid.w + grid.y || abs(section.x - storage.x) > viewDistance ||
        abs(section.z - storage.z) > viewDistance) {
        return false;
    }
    int gx = chrFloorMod(section.x, grid.x);
    int gy = section.y - grid.w;
    int gz = chrFloorMod(section.z, grid.z);
    index = uint((gz * grid.y + gy) * grid.x + gx);
    return true;
}

uint chrStaticLightCount(ChrChunkLights c) {
    return c.staticLightAddress != 0ul ? min(c.staticLightCount, CHR_MAX_LIGHTS_PER_SECTION) : 0u;
}

uint chrEntityLightCount(ChrChunkLights c) {
    uint s = chrStaticLightCount(c);
    return c.entityLightAddress != 0ul ? min(c.entityLightCount, CHR_MAX_LIGHTS_PER_SECTION - s) : 0u;
}

ChrPackedLight chrLoadLight(ChrChunkLights c, uint i) {
    uint s = chrStaticLightCount(c);
    if (i < s) { return ChrPackedLightBuffer(c.staticLightAddress).lights[i]; }
    return ChrPackedLightBuffer(c.entityLightAddress).lights[i - s];
}

float chrBlockLightFade(float dist) {
    float range = max(float(CHR_BLOCK_LIGHT_RANGE), 1.0);
    float t = clamp(dist / range, 0.0, 1.0);
    // Smooth roll-off that reaches exactly zero at the range.
    float f = 1.0 - t * t;
    return f * f;
}

// Biome tint of the water the current point is in, for shadow rays leaving through the water surface.
uint chrShadowWaterTint = 0u;

// Shadow ray toward a point (or direction when tMax is large). Returns the transmitted fraction.
vec3 chrTraceShadow(vec3 origin, vec3 dir, float tMax, uint mask, bool insideBoat) {
    shadowRay.throughput = vec3(1.0);
    shadowRay.visible = (insideBoat ? 2u : 0u) | (chrShadowWaterTint << 8u);
    traceRayEXT(topLevelAS, gl_RayFlagsNoneEXT, mask, 0, 0, 0, origin, 0.0002, dir, tMax, 1);
    return (shadowRay.visible & 1u) != 0u ? shadowRay.throughput : vec3(0.0);
}

// Shadow of the vanilla block clouds: a second shadow ray that only sees the cloud geometry. Shadow rays always use
// the "shadow" hit group (Radiance puts it first in every instance's records and shadow rays use SBT offset 0),
// so the clouds go through shadow.rahit like any translucent block. Kept separate so its strength can be set.
vec3 chrBlockCloudShadow(vec3 p, vec3 ng, vec3 l, bool insideBoat) {
    vec3 tc = chrTraceShadow(p + (dot(l, ng) >= 0.0 ? ng : -ng) * 0.0003, l, 1000.0, CLOUD_MASK, insideBoat);
    return mix(vec3(1.0), tc, clamp(float(CHR_CLOUD_SHADOW_STRENGTH), 0.0, 1.0));
}

// Offsets a ray origin off the surface on the side the ray leaves through.
vec3 chrOffsetOrigin(vec3 p, vec3 ng, vec3 dir, float bias) {
    return p + (dot(dir, ng) >= 0.0 ? ng : -ng) * bias;
}

// Sun or moon light arriving at a surface point, including the shadow ray.
vec3 chrSampleCelestialLight(ChrPalette pal, ChrSurface s, vec3 p, vec3 n, vec3 ng, vec3 v, bool opaque,
                             bool insideBoat, inout uint seed) {
    if (worldUBO.skyType != 1u) { return vec3(0.0); }
    if (max(pal.lightColor.r, max(pal.lightColor.g, pal.lightColor.b)) <= 1e-6) { return vec3(0.0); }

    float softness = max(float(CHR_SUN_SOFTNESS), 0.0);
    // Moonlight uses the same small light size as sunlight: a wider source only adds noise, which the upscaler
    // then magnifies into blotches of fake light on distant hills.
    float moonBlur = 0.0;
    float cosMax = cos(0.0093 * (0.3 + softness + moonBlur));
    vec3 l = chrToWorld(chrUniformCone(vec2(rand(seed), rand(seed)), cosMax), pal.lightDir);
    if (opaque && s.subsurface <= 0.0 && dot(l, ng) <= 0.0) { return vec3(0.0); }

    vec3 f = chrEvalBrdfCos(s, n, v, l);
    if (max(f.r, max(f.g, f.b)) <= 1e-7) { return vec3(0.0); }

    uint mask = WORLD_MASK | PLAYER_MASK;
    vec3 t = chrTraceShadow(chrOffsetOrigin(p, ng, l, 0.0003), l, 1000.0, mask, insideBoat);
    if (CHR_CLOUD_MODE == CHR_CLOUD_MODE_VOLUMETRIC) { t *= chrCloudShadowAt(p, pal.lightDir); }
    if (CHR_CLOUD_MODE == CHR_CLOUD_MODE_BLOCK && max(t.r, max(t.g, t.b)) > 0.0) { t *= chrBlockCloudShadow(p, ng, l, insideBoat); }
    return pal.lightColor * f * t;
}

// One block light sample (resampled from CHR_BLOCK_LIGHT_CANDIDATES candidates) with its shadow ray.
// The chunk sections whose lights a shading point samples, gathered once per point and shared by its light
// samples. Only the 2 x 2 x 2 sections nearest to the point: on each axis its own section and the neighbour on the
// side it is closer to. Lights in the far neighbours are at least 8 blocks away and mostly faded out by the range,
// and skipping them reads 8 section headers instead of 27.
struct ChrLightSections {
    uint index[8];
    uint end[8];
    int count;
    uint total;
};

ChrLightSections chrGatherLightSections(vec3 p) {
    ChrLightSections ls;
    ls.count = 0;
    ls.total = 0u;
    dvec3 absP = worldUBO.cameraPos.xyz + dvec3(p);
    ivec3 center = ivec3(floor(absP / 16.0));
    vec3 within = vec3(absP - dvec3(center) * 16.0) / 16.0;
    ivec3 side = ivec3(step(vec3(0.5), within)) * 2 - 1;
    for (int i = 0; i < 8; ++i) {
        ivec3 section = center + ivec3(i & 1, (i >> 1) & 1, (i >> 2) & 1) * side;
        uint index;
        if (!chrSectionIndex(section, index)) { continue; }
        ChrChunkLights c = chrChunkLights[index];
        if (c.originX != section.x * 16 || c.originY != section.y * 16 || c.originZ != section.z * 16) { continue; }
        uint count = chrStaticLightCount(c) + chrEntityLightCount(c);
        if (count == 0u) { continue; }
        ls.total += count;
        ls.index[ls.count] = index;
        ls.end[ls.count] = ls.total;
        ++ls.count;
    }
    return ls;
}

vec3 chrSampleBlockLight(ChrSurface s, vec3 p, vec3 n, vec3 ng, vec3 v, bool opaque, bool insideBoat,
                         ChrLightSections ls, inout uint seed) {
    uint total = ls.total;
    if (total == 0u) { return vec3(0.0); }

    dvec3 cameraPos = worldUBO.cameraPos.xyz;
    float strength = max(float(CHR_BLOCK_LIGHT_STRENGTH), 0.0) * CHR_BLOCK_LIGHT_SCALE;
    int candidates = clamp(int(CHR_BLOCK_LIGHT_CANDIDATES), 1, 32);

    float wSum = 0.0;
    float chosenTarget = 0.0;
    vec3 chosenContribution = vec3(0.0);
    vec3 chosenDir = vec3(0.0);
    float chosenDist = 0.0;

    for (int i = 0; i < candidates; ++i) {
        uint pick = min(uint(rand(seed) * float(total)), total - 1u);
        int k = 0;
        while (k < ls.count - 1 && pick >= ls.end[k]) { ++k; }
        uint first = k == 0 ? 0u : ls.end[k - 1];
        ChrChunkLights c = chrChunkLights[ls.index[k]];
        ChrPackedLight light = chrLoadLight(c, pick - first);
        // Lights on entities (dropped light blocks such as glowstone or torches, held items, glowing mobs) are tiny
        // compared with the block they stand for: a dropped glowstone is a quarter-size cube. Boost them so they
        // light their surroundings the way players expect.
        bool entityLight = (pick - first) >= chrStaticLightCount(c);

        float area = max(light.p0Area.w, 0.0);
        if (area <= 1e-8) { continue; }
        float r1 = sqrt(rand(seed));
        float r2 = rand(seed);
        vec3 lp = light.p0Area.xyz * (1.0 - r1) + light.p1.xyz * (r1 * (1.0 - r2)) + light.p2.xyz * (r1 * r2);
        vec3 toLight = vec3(dvec3(lp) - cameraPos) - p;
        float dist2 = dot(toLight, toLight);
        float dist = sqrt(dist2);
        if (dist <= 1e-3) { continue; }
        float fade = chrBlockLightFade(dist);
        if (fade <= 0.0) { continue; }
        vec3 l = toLight / dist;
        if (opaque && s.subsurface <= 0.0 && dot(l, ng) <= 0.0) { continue; }
        float cosLight = abs(dot(light.normal.xyz, l));
        if (cosLight <= 1e-4) { continue; }

        vec3 f = chrEvalBrdfCos(s, n, v, l);
        vec3 le = max(light.radiance.rgb, vec3(0.0)) * max(light.radiance.a, 1.0) * strength * fade;
        if (entityLight) {
            // Mob eyes and glowing body parts (spider and cave spider eyes, endermen, endermites, phantoms...) do not
            // light the world: their glow stays on their own pixels (world/eyes.rchit). Mob glow is red, magenta or
            // purple; dropped light blocks glow warm white, yellow, orange or cyan and keep lighting their
            // surroundings. (A dropped redstone torch is caught as well, a fair trade.)
            vec3 rc = max(light.radiance.rgb, vec3(0.0));
            float peak = max(rc.r, max(rc.g, rc.b));
            float saturation = peak > 0.0 ? (peak - min(rc.r, min(rc.g, rc.b))) / peak : 0.0;
            float purple = smoothstep(1.0, 1.25, min(rc.r, rc.b) / max(rc.g, 1e-4));   // red and blue above green
            float red = smoothstep(1.8, 2.4, rc.r / max(max(rc.g, rc.b), 1e-4));       // red far above the rest
            float notEyes = 1.0 - max(purple, red) * smoothstep(0.2, 0.4, saturation);
            le *= max(float(CHR_ENTITY_LIGHT_BOOST), 0.0) * notEyes;
        } else {
            // Weak glow from resource packs (glowing ore pixels, glow lichen, dim decorative emission) mostly lights
            // only itself; real light sources (torches, lanterns, glowstone, end rods, lava...) glow much brighter
            // and keep their full light. Peak radiance = pixel colour x labPBR emission.
            float peak = max(light.radiance.r, max(light.radiance.g, light.radiance.b));
            float weakKeep = clamp(float(CHR_WEAK_EMITTER_LIGHT), 0.0, 1.0);
            le *= mix(weakKeep, 1.0, smoothstep(0.15, 0.4, peak));
        }
        // Soften the inverse square close to the light (within about half a block) so the block a light is mounted on
        // does not blow out into a white hot spot.
        vec3 contribution = le * f * cosLight / (dist2 + 0.25);
        float target = chrLuminance(contribution);
        if (!(target > 0.0) || isinf(target)) { continue; }
        // Source pdf = 1 / (total * area)
        float w = target * float(total) * area;
        wSum += w;
        if (rand(seed) * wSum <= w) {
            chosenTarget = target;
            chosenContribution = contribution;
            chosenDir = l;
            chosenDist = dist;
        }
    }
    if (wSum <= 0.0 || chosenTarget <= 0.0) { return vec3(0.0); }

    uint mask = WORLD_MASK | PLAYER_MASK;
    vec3 origin = chrOffsetOrigin(p, ng, chosenDir, 0.0003);
    vec3 t = chrTraceShadow(origin, chosenDir, max(chosenDist - 0.004, 0.001), mask, insideBoat);
    vec3 result = chosenContribution / chosenTarget * (wSum / float(candidates)) * t;
    // Firefly clamp: a rare, very bright sample (a small light found from far away) would otherwise be spread by
    // the upscaler into a glowing patch over the background.
    float lum = chrLuminance(result);
    float maxSample = max(float(CHR_LIGHT_SAMPLE_CLAMP), 0.1);
    return lum > maxSample ? result * (maxSample / lum) : result;
}

#endif
