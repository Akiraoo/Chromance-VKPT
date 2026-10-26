#ifndef CHR_BRDF_GLSL
#define CHR_BRDF_GLSL

// Surface reflectance: Lambert diffuse plus a GGX specular lobe (height-correlated Smith visibility,
// visible-normal sampling). Roughness values in this file are GGX alpha unless stated otherwise.

#ifndef PI
#    define PI 3.14159265358979323
#endif
#ifndef INV_PI
#    define INV_PI 0.31830988618379067
#endif

const vec3 CHR_LUMA = vec3(0.2126, 0.7152, 0.0722);

float chrLuminance(vec3 color) {
    return dot(color, CHR_LUMA);
}

bool chrFinite(vec3 value) {
    return !any(isnan(value)) && !any(isinf(value));
}

bool chrFinite(float value) {
    return !isnan(value) && !isinf(value);
}

vec3 chrSafeNormalize(vec3 value, vec3 fallback) {
    float len2 = dot(value, value);
    if (!(len2 > 1e-12) || isinf(len2)) { return fallback; }
    return value * inversesqrt(len2);
}

void chrBasis(vec3 n, out vec3 t, out vec3 b) {
    float s = n.z >= 0.0 ? 1.0 : -1.0;
    float a = -1.0 / (s + n.z);
    float c = n.x * n.y * a;
    t = vec3(1.0 + s * n.x * n.x * a, s * c, -s * n.x);
    b = vec3(c, s + n.y * n.y * a, -n.y);
}

vec3 chrToWorld(vec3 local, vec3 n) {
    vec3 t, b;
    chrBasis(n, t, b);
    return t * local.x + b * local.y + n * local.z;
}

vec3 chrCosineHemisphere(vec2 u) {
    float r = sqrt(u.x);
    float phi = 2.0 * PI * u.y;
    return vec3(r * cos(phi), r * sin(phi), sqrt(max(1.0 - u.x, 0.0)));
}

// Uniform direction inside a cone of half-angle acos(cosMax) around +Z.
vec3 chrUniformCone(vec2 u, float cosMax) {
    float cosTheta = mix(1.0, cosMax, u.x);
    float sinTheta = sqrt(max(1.0 - cosTheta * cosTheta, 0.0));
    float phi = 2.0 * PI * u.y;
    return vec3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
}

vec3 chrFresnelSchlick(vec3 f0, float cosTheta) {
    float m = clamp(1.0 - cosTheta, 0.0, 1.0);
    float m2 = m * m;
    return f0 + (vec3(1.0) - f0) * (m2 * m2 * m);
}

// Exact dielectric Fresnel. eta = n_incident / n_transmitted.
float chrDielectricFresnel(float cosI, float eta) {
    cosI = clamp(cosI, 0.0, 1.0);
    float sinT2 = eta * eta * (1.0 - cosI * cosI);
    if (sinT2 >= 1.0) { return 1.0; }
    float cosT = sqrt(1.0 - sinT2);
    float rs = (eta * cosI - cosT) / (eta * cosI + cosT);
    float rp = (cosI - eta * cosT) / (cosI + eta * cosT);
    return 0.5 * (rs * rs + rp * rp);
}

float chrGgxD(float NoH, float a2) {
    float d = (NoH * a2 - NoH) * NoH + 1.0;
    return a2 / max(PI * d * d, 1e-8);
}

// Height-correlated Smith visibility V = G2 / (4 NoL NoV).
float chrSmithV(float NoV, float NoL, float a2) {
    float gv = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float gl = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-8);
}

float chrSmithG1(float NoX, float a2) {
    return 2.0 * NoX / max(NoX + sqrt(a2 + (1.0 - a2) * NoX * NoX), 1e-8);
}

// Visible normal sampling (Heitz 2018), view direction in tangent space.
vec3 chrSampleVndf(vec3 v, float alpha, vec2 u) {
    vec3 vh = normalize(vec3(alpha * v.x, alpha * v.y, v.z));
    float lensq = vh.x * vh.x + vh.y * vh.y;
    vec3 t1 = lensq > 0.0 ? vec3(-vh.y, vh.x, 0.0) * inversesqrt(lensq) : vec3(1.0, 0.0, 0.0);
    vec3 t2 = cross(vh, t1);
    float r = sqrt(u.x);
    float phi = 2.0 * PI * u.y;
    float p1 = r * cos(phi);
    float p2 = r * sin(phi);
    float s = 0.5 * (1.0 + vh.z);
    p2 = (1.0 - s) * sqrt(max(1.0 - p1 * p1, 0.0)) + s * p2;
    vec3 nh = p1 * t1 + p2 * t2 + sqrt(max(0.0, 1.0 - p1 * p1 - p2 * p2)) * vh;
    return normalize(vec3(alpha * nh.x, alpha * nh.y, max(nh.z, 1e-6)));
}

struct ChrSurface {
    vec3 albedo;
    vec3 f0;
    float alpha;        // GGX alpha
    float metallic;
    float subsurface;   // labPBR subsurface amount, used for back lighting of thin foliage
    float ao;
};

vec3 chrDiffuseColor(ChrSurface s) {
    return s.albedo * (1.0 - s.metallic);
}

vec3 chrSpecularColor(ChrSurface s) {
    return mix(s.f0, s.albedo, s.metallic);
}

// BRDF * cos(theta_l). Returns zero for directions below the shading normal unless the surface scatters light
// through (subsurface).
// Surfaces this smooth reflect light sources through their reflection rays instead of explicit light sampling.
const float CHR_SHARP_ALPHA = 0.02;

bool chrIsSharp(ChrSurface s) {
    return s.alpha < CHR_SHARP_ALPHA;
}

vec3 chrEvalBrdfCos(ChrSurface s, vec3 n, vec3 v, vec3 l) {
    float NoV = max(dot(n, v), 1e-4);
    float NoL = dot(n, l);
    if (NoL <= 0.0) {
        if (s.subsurface <= 0.0) { return vec3(0.0); }
        // Light passing through a thin leaf: soft wrap toward the back side.
        return chrDiffuseColor(s) * s.subsurface * INV_PI * 0.6 * (-NoL);
    }
    vec3 h = normalize(v + l);
    float NoH = max(dot(n, h), 0.0);
    float VoH = max(dot(v, h), 0.0);
    float a2 = max(s.alpha * s.alpha, 1e-7);
    vec3 specColor = chrSpecularColor(s);
    vec3 F = chrFresnelSchlick(specColor, VoH);
    vec3 spec = chrIsSharp(s) ? vec3(0.0) : F * (chrGgxD(NoH, a2) * chrSmithV(NoV, NoL, a2));
    vec3 diffuse = chrDiffuseColor(s) * INV_PI * (vec3(1.0) - chrFresnelSchlick(specColor, NoV));
    return (diffuse + spec) * NoL;
}

// Probability of picking the specular lobe.
float chrSpecularProbability(ChrSurface s, vec3 n, vec3 v) {
    float NoV = max(dot(n, v), 1e-4);
    vec3 specColor = chrSpecularColor(s);
    float spec = chrLuminance(chrFresnelSchlick(specColor, NoV));
    float diff = chrLuminance(chrDiffuseColor(s)) * (1.0 - spec);
    if (diff <= 1e-5) { return 1.0; }
    // Rough dielectrics barely reflect anything visible: keep a small floor so highlights still converge.
    float p = clamp(spec / (spec + diff), 0.06, 0.94);
    // Mirror-like surfaces (puddles, polished blocks): spend at least half the samples on the reflection so it
    // resolves cleanly instead of being lost in noise.
    return chrIsSharp(s) ? max(p, 0.5) : p;
}

// Samples the next direction. Returns false when the path should end. weight = BRDF * cos / pdf.
bool chrSampleBrdf(ChrSurface s, vec3 n, vec3 ng, vec3 v, vec2 u, float lobeSelect, out vec3 l, out vec3 weight,
                   out uint lobe) {
    float pSpec = chrSpecularProbability(s, n, v);
    vec3 specColor = chrSpecularColor(s);
    float NoV = max(dot(n, v), 1e-4);
    if (lobeSelect < pSpec) {
        lobe = 1u;
        vec3 t, b;
        chrBasis(n, t, b);
        vec3 vLocal = vec3(dot(v, t), dot(v, b), NoV);
        float alpha = max(s.alpha, 0.002);
        vec3 hLocal = chrSampleVndf(vLocal, alpha, u);
        vec3 h = t * hLocal.x + b * hLocal.y + n * hLocal.z;
        l = reflect(-v, h);
        float NoL = dot(n, l);
        if (NoL <= 0.0 || dot(ng, l) <= 0.0) {
            weight = vec3(0.0);
            return false;
        }
        float VoH = max(dot(v, h), 0.0);
        float a2 = alpha * alpha;
        vec3 F = chrFresnelSchlick(specColor, VoH);
        weight = F * (chrSmithG1(NoL, a2)) / pSpec;
        return true;
    }
    lobe = 0u;
    l = chrToWorld(chrCosineHemisphere(u), n);
    if (dot(ng, l) <= 0.0) {
        // Normal maps can push the hemisphere below the geometry; fold it back instead of losing the sample.
        l = reflect(l, ng);
    }
    vec3 diffuse = chrDiffuseColor(s) * (vec3(1.0) - chrFresnelSchlick(specColor, NoV));
    weight = diffuse * s.ao / (1.0 - pSpec);
    return true;
}

#endif
