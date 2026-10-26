#ifndef CHR_PAYLOAD_GLSL
#define CHR_PAYLOAD_GLSL

// Ray payloads shared by the ray generation, hit and miss shaders.
//
// The main ray carries the path state between bounces. The closest-hit shader does all shading for the surface it
// hits (emission, sun / moon light, block lights) and then picks the next direction; the ray generation shader
// only loops. The material of the hit is packed into the payload so the ray generation shader can fill the
// denoiser guide images for the first hit.

struct ChrRay {
    vec3 origin;
    float hitT;

    vec3 direction;
    uint seed;

    vec3 radiance;
    float coneWidth;

    vec3 throughput;
    float coneSpread;

    vec3 normal;
    uint state;

    vec3 prevScenePos;
    uint hasPrevScenePos;

    vec3 directLight;
    uint packedAlbedo;

    uvec4 packedMaterial;
};

struct ChrShadowRay {
    vec3 throughput;
    uint visible;   // bit 0 light visible, bit 1 inside boat, bit 2 water probe; bits 8-31 water tint (RGB8)
};

// State bits
const uint CHR_BOUNCE_MASK = 0xFFu;
const uint CHR_INSIDE_BOAT_BIT = 1u << 8u;
const uint CHR_STOP_BIT = 1u << 9u;
const uint CHR_CONTINUE_BIT = 1u << 10u;
const uint CHR_NOISY_BIT = 1u << 11u;
const uint CHR_LOBE_SHIFT = 12u;
const uint CHR_LOBE_MASK = 0x3u << 12u;
const uint CHR_SKIP_FOG_BIT = 1u << 14u;
const uint CHR_IGNORE_WATER_SELF_BIT = 1u << 15u;
// The ray that produced the current hit was sampled from a diffuse lobe. Block lights and the sun / moon are
// sampled explicitly at every diffuse bounce, so such rays must not pick them up a second time.
const uint CHR_FROM_DIFFUSE_BIT = 1u << 16u;
// The ray is travelling through water (used for absorption).
const uint CHR_IN_WATER_BIT = 1u << 17u;
// The ray is still on the camera segment; underwater fog for that segment is applied by the ray generation shader.
const uint CHR_CAMERA_SEGMENT_BIT = 1u << 18u;
// The current hit is the water surface (needs a larger origin offset for the next ray).
const uint CHR_WATER_SURFACE_BIT = 1u << 19u;
// The current hit is a transmissive surface (water, glass).
const uint CHR_TRANSMISSIVE_BIT = 1u << 20u;
// The ray left a mirror-like surface (or is a refraction): it may see the sun / moon discs and block light
// emission sharply. Light sources are not also sampled for such surfaces, so nothing is counted twice.
const uint CHR_SHARP_BIT = 1u << 21u;
// The primary hit carries rain ripples. Ripples belong to the surface, not to what it reflects, so the denoiser
// must move their history with the surface instead of with the reflected scene.
const uint CHR_RIPPLE_BIT = 1u << 22u;

const uint CHR_LOBE_DIFFUSE = 0u;
const uint CHR_LOBE_SPECULAR = 1u;
const uint CHR_LOBE_TRANSMISSION = 2u;

// The payloads stay at their original size. The biome colour of the water a ray travels through (24-bit RGB,
// 0 = unknown) rides in the upper bits of fields that only use their lowest bits: ChrRay.hasPrevScenePos (bit 0)
// and ChrShadowRay.visible (bits 0-2).
uint chrRayWaterTint(ChrRay r) { return r.hasPrevScenePos >> 8u; }
void chrSetRayWaterTint(inout ChrRay r, uint tint) { r.hasPrevScenePos = (r.hasPrevScenePos & 0xffu) | (tint << 8u); }
bool chrRayHasPrevScenePos(ChrRay r) { return (r.hasPrevScenePos & 1u) != 0u; }
void chrSetRayHasPrevScenePos(inout ChrRay r, bool v) { r.hasPrevScenePos = (r.hasPrevScenePos & ~1u) | (v ? 1u : 0u); }

void chrSetBit(inout ChrRay ray, uint bit, bool enabled) {
    ray.state = enabled ? (ray.state | bit) : (ray.state & ~bit);
}

bool chrHasBit(ChrRay ray, uint bit) {
    return (ray.state & bit) != 0u;
}

void chrSetBounce(inout ChrRay ray, uint bounce) {
    ray.state = (ray.state & ~CHR_BOUNCE_MASK) | (bounce & CHR_BOUNCE_MASK);
}

uint chrBounce(ChrRay ray) {
    return ray.state & CHR_BOUNCE_MASK;
}

void chrSetLobe(inout ChrRay ray, uint lobe) {
    ray.state = (ray.state & ~CHR_LOBE_MASK) | ((lobe & 0x3u) << CHR_LOBE_SHIFT);
}

uint chrLobe(ChrRay ray) {
    return (ray.state & CHR_LOBE_MASK) >> CHR_LOBE_SHIFT;
}

struct ChrMaterial {
    vec4 albedo;
    vec3 f0;
    float roughness;
    float metallic;
    float transmission;
    float ior;
    float emission;
};

uint chrPackUnorm3x8Plus8(vec3 a, float b) {
    return packUnorm4x8(vec4(clamp(a, vec3(0.0), vec3(1.0)), clamp(b, 0.0, 1.0)));
}

void chrStoreMaterial(inout ChrRay ray, ChrMaterial mat) {
    ray.packedAlbedo = packUnorm4x8(clamp(mat.albedo, vec4(0.0), vec4(1.0)));
    ray.packedMaterial.x = chrPackUnorm3x8Plus8(mat.f0, mat.roughness);
    ray.packedMaterial.y = packHalf2x16(vec2(mat.metallic, mat.transmission));
    ray.packedMaterial.z = packHalf2x16(vec2(mat.ior, mat.emission));
}

ChrMaterial chrLoadMaterial(ChrRay ray) {
    ChrMaterial mat;
    mat.albedo = unpackUnorm4x8(ray.packedAlbedo);
    vec4 f0r = unpackUnorm4x8(ray.packedMaterial.x);
    mat.f0 = f0r.rgb;
    mat.roughness = f0r.a;
    vec2 mt = unpackHalf2x16(ray.packedMaterial.y);
    vec2 ie = unpackHalf2x16(ray.packedMaterial.z);
    mat.metallic = mt.x;
    mat.transmission = mt.y;
    mat.ior = ie.x;
    mat.emission = ie.y;
    return mat;
}

void chrClearMaterial(inout ChrRay ray) {
    ray.packedAlbedo = 0u;
    ray.packedMaterial = uvec4(0u, packHalf2x16(vec2(0.0)), packHalf2x16(vec2(1.0, 0.0)), 0u);
}

#endif
