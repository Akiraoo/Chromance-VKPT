#ifndef CHR_TEXTURING_GLSL
#define CHR_TEXTURING_GLSL

// Sampling helpers for atlas textures (albedo and labPBR maps). Lookups are clamped to the sprite's rectangle so
// neighbouring sprites never bleed in.

int chrAtlasLevel(sampler2D tex, vec2 uvMin, vec2 uvMax, float lod) {
    int levels = max(textureQueryLevels(tex), 1);
    ivec2 base = textureSize(tex, 0);
    vec2 spritePixels = max(abs(uvMax - uvMin) * vec2(base), vec2(1.0));
    int maxSafe = int(floor(log2(max(min(spritePixels.x, spritePixels.y), 1.0))));
    return clamp(int(floor(max(lod, 0.0))), 0, min(levels - 1, maxSafe));
}

ivec2 chrClampTexel(ivec2 texel, vec2 uvMin, vec2 uvMax, ivec2 size) {
    ivec2 lo = ivec2(floor(min(uvMin, uvMax) * vec2(size)));
    ivec2 hi = ivec2(ceil(max(uvMin, uvMax) * vec2(size))) - ivec2(1);
    lo = clamp(lo, ivec2(0), size - ivec2(1));
    hi = clamp(max(hi, lo), ivec2(0), size - ivec2(1));
    return clamp(texel, lo, hi);
}

vec4 chrSampleAtlas(sampler2D tex, vec2 uv, vec2 uvMin, vec2 uvMax, float lod, bool bilinear) {
    ivec2 base = textureSize(tex, 0);
    if (base.x <= 0 || base.y <= 0) { return vec4(0.0); }
    int level = chrAtlasLevel(tex, uvMin, uvMax, lod);
    ivec2 size = max(textureSize(tex, level), ivec2(1));
    if (!bilinear) { return texelFetch(tex, chrClampTexel(ivec2(floor(uv * vec2(size))), uvMin, uvMax, size), level); }
    vec2 pixel = uv * vec2(size) - 0.5;
    ivec2 p0 = ivec2(floor(pixel));
    vec2 f = fract(pixel);
    vec4 c00 = texelFetch(tex, chrClampTexel(p0, uvMin, uvMax, size), level);
    vec4 c10 = texelFetch(tex, chrClampTexel(p0 + ivec2(1, 0), uvMin, uvMax, size), level);
    vec4 c01 = texelFetch(tex, chrClampTexel(p0 + ivec2(0, 1), uvMin, uvMax, size), level);
    vec4 c11 = texelFetch(tex, chrClampTexel(p0 + ivec2(1, 1), uvMin, uvMax, size), level);
    return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

// labPBR specular map: emission (alpha) must never be filtered, so it is fetched separately at full resolution.
vec4 chrSampleSpecular(sampler2D tex, vec2 uv, vec2 uvMin, vec2 uvMax, float lod, bool bilinear) {
    vec4 s = chrSampleAtlas(tex, uv, uvMin, uvMax, lod, bilinear);
    ivec2 size = textureSize(tex, 0);
    if (size.x > 0 && size.y > 0) {
        s.a = texelFetch(tex, chrClampTexel(ivec2(floor(uv * vec2(size))), uvMin, uvMax, size), 0).a;
    }
    return s;
}

#endif
