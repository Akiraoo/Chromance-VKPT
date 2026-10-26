#ifndef CHR_MATERIAL_GLSL
#define CHR_MATERIAL_GLSL

// labPBR 1.3 decoding (https://shaderlabs.org/wiki/LabPBR_Material_Standard).
//   specular: R = perceptual smoothness, G = F0 / metal id, B = porosity / subsurface, A = emission (255 = none)
//   normal:   RG = normal XY, B = ambient occlusion, A = height

const vec4 CHR_DEFAULT_SPECULAR = vec4(0.0);
const vec4 CHR_DEFAULT_NORMAL = vec4(0.5, 0.5, 1.0, 1.0);

struct ChrLabPbr {
    vec3 albedo;
    vec3 f0;
    float perceptualRoughness;
    float alpha;          // GGX alpha
    float metallic;
    float subsurface;
    float porosity;
    float transmission;
    float ior;
    float emission;
    vec3 tangentNormal;
    float ao;
};

// Complex index of refraction (n, k) of the predefined labPBR metals 230..237.
void chrHardcodedMetal(int id, out vec3 n, out vec3 k) {
    if (id == 230) { n = vec3(2.9114, 2.9497, 2.5845); k = vec3(3.0893, 2.9318, 2.7670); }       // iron
    else if (id == 231) { n = vec3(0.18299, 0.42108, 1.3734); k = vec3(3.4242, 2.3459, 1.7704); } // gold
    else if (id == 232) { n = vec3(1.3456, 0.96521, 0.61722); k = vec3(7.4746, 6.3995, 5.3031); } // aluminium
    else if (id == 233) { n = vec3(3.1071, 3.1812, 2.3230); k = vec3(3.3314, 3.3291, 3.1350); }   // chrome
    else if (id == 234) { n = vec3(0.27105, 0.67693, 1.3164); k = vec3(3.6092, 2.6248, 2.2921); } // copper
    else if (id == 235) { n = vec3(1.9100, 1.8300, 1.4400); k = vec3(3.5100, 3.4000, 3.1800); }   // lead
    else if (id == 236) { n = vec3(2.3757, 2.0847, 1.8453); k = vec3(4.2655, 3.7153, 3.1365); }   // platinum
    else { n = vec3(0.15943, 0.14512, 0.13547); k = vec3(3.9291, 3.1900, 2.3808); }              // silver
}

vec3 chrConductorF0(vec3 n, vec3 k) {
    vec3 k2 = k * k;
    return ((n - 1.0) * (n - 1.0) + k2) / max((n + 1.0) * (n + 1.0) + k2, vec3(1e-6));
}

ChrLabPbr chrDecodeLabPbr(vec4 albedo, vec4 specular, vec4 normal) {
    ChrLabPbr m;
    float smoothness = clamp(specular.r, 0.0, 1.0);
    m.perceptualRoughness = clamp(1.0 - smoothness, 0.03, 1.0);
    m.alpha = m.perceptualRoughness * m.perceptualRoughness;

    float b = specular.b * 255.0;
    m.porosity = b < 64.5 ? b / 64.0 : 0.0;
    m.subsurface = b >= 64.5 ? (b - 65.0) / 190.0 : 0.0;

    int emissionId = int(round(specular.a * 255.0));
    m.emission = emissionId >= 255 ? 0.0 : float(emissionId) / 254.0;

    int metalId = int(round(specular.g * 255.0));
    m.albedo = albedo.rgb;
    m.transmission = 0.0;
    m.ior = 1.5;
    if (metalId < 230) {
        float f0 = max(specular.g, 0.02);
        m.f0 = vec3(f0);
        m.metallic = 0.0;
        float sf0 = sqrt(min(f0, 0.9));
        m.ior = (1.0 + sf0) / max(1.0 - sf0, 1e-4);
        m.transmission = clamp(1.0 - albedo.a, 0.0, 1.0);
    } else if (metalId <= 237) {
        vec3 n, k;
        chrHardcodedMetal(metalId, n, k);
        m.f0 = chrConductorF0(n, k);
        m.metallic = 1.0;
    } else {
        m.f0 = albedo.rgb;
        m.metallic = 1.0;
    }

    vec2 xy = normal.xy * 2.0 - 1.0;
    m.tangentNormal = vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
    m.ao = clamp(normal.b, 0.0, 1.0);
    return m;
}

#endif
