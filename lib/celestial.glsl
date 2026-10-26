#ifndef CHR_CELESTIAL_GLSL
#define CHR_CELESTIAL_GLSL

// Visible sun and moon. Shape is selectable: a round disc, or a square like vanilla Minecraft.
// The square moon uses the vanilla moon-phase texture; the round moon is drawn with its phase terminator.
// Requires textures[], skyUBO and lib/palette.glsl.

const float CHR_SUN_ANGULAR_RADIUS = 0.030;   // radians, before the size setting
const float CHR_MOON_ANGULAR_RADIUS = 0.034;

void chrDiscBasis(vec3 n, out vec3 right, out vec3 up) {
    // Keep the square aligned with the sun path (east-west) so it does not spin.
    vec3 axis = abs(n.x) < 0.95 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);
    up = normalize(cross(axis, n));
    right = normalize(cross(n, up));
}

// Local coordinates of a direction on the disc plane, scaled so the disc edge is at 1.
vec2 chrDiscCoord(vec3 dir, vec3 center, float radius, out bool front) {
    float z = dot(dir, center);
    front = z > 0.0;
    vec3 right, up;
    chrDiscBasis(center, right, up);
    vec2 q = vec2(dot(dir, right), dot(dir, up)) / max(z, 1e-4);
    return q / tan(radius);
}

// Shape distance: 0 at the centre, 1 at the nominal edge. Round = circle, square = vanilla-style square.
float chrShapeDistance(vec2 q) {
    return CHR_CELESTIAL_SHAPE == CHR_SHAPE_SQUARE ? max(abs(q.x), abs(q.y)) : length(q);
}

// Sun: no disc texture, just a ball of light. A soft bright core that the tone mapper burns to white, a warm
// glow around it and a wide faint glare. No hard edge anywhere.
vec3 chrSunDisc(ChrPalette p, vec3 dir) {
    float radius = CHR_SUN_ANGULAR_RADIUS * max(float(CHR_SUN_SIZE), 0.1);
    bool front;
    vec2 q = chrDiscCoord(dir, p.sunDir, radius, front);
    if (!front) { return vec3(0.0); }
    vec3 base = p.sunRadiance / CHR_SUN_INTENSITY;
    float visibility = 1.0 - p.rain;
    if (visibility <= 0.0 || max(base.r, max(base.g, base.b)) <= 0.0) { return vec3(0.0); }
    float r = chrShapeDistance(q);
    float core = exp(-r * r * 2.2) * 260.0;
    float glow = exp(-r * 1.1) * 9.0;
    float glare = exp(-r * 0.22) * 0.9;
    vec3 warm = mix(vec3(1.0, 0.78, 0.55), vec3(1.0), 0.45);
    return (base * core + base * warm * (glow + glare)) * visibility;
}

// Moon: a pale, soft glow (brightness follows the phase), no texture.
vec3 chrMoonDisc(ChrPalette p, vec3 dir) {
    float radius = CHR_MOON_ANGULAR_RADIUS * max(float(CHR_MOON_SIZE), 0.1);
    bool front;
    vec2 q = chrDiscCoord(dir, -p.sunDir, radius, front);
    if (!front) { return vec3(0.0); }
    float r = chrShapeDistance(q);
    float phase = chrMoonPhaseBrightness(skyUBO.moonPhase);
    // No wide faint tail: a very smooth dim gradient over a dark sky only shows up as 8-bit rings.
    float light = (exp(-r * r * 2.5) * 1.4 + exp(-r * 1.6) * 0.10) * phase;
    vec3 tint = chrDesaturate(vec3(0.82, 0.88, 1.0), float(CHR_NIGHT_DESATURATION));
    float visibility = smoothstep(-0.05, 0.05, -p.sunDir.y + 0.08) * (1.0 - p.rain);
    return tint * light * visibility * max(float(CHR_NIGHT_BRIGHTNESS), 0.0);
}

bool chrCelestialCovers(ChrPalette p, vec3 dir) {
    bool front;
    float sunRadius = CHR_SUN_ANGULAR_RADIUS * max(float(CHR_SUN_SIZE), 0.1);
    vec2 qs = chrDiscCoord(dir, p.sunDir, sunRadius, front);
    if (front && max(abs(qs.x), abs(qs.y)) < 1.0) { return true; }
    float moonRadius = CHR_MOON_ANGULAR_RADIUS * max(float(CHR_MOON_SIZE), 0.1);
    vec2 qm = chrDiscCoord(dir, -p.sunDir, moonRadius, front);
    return front && max(abs(qm.x), abs(qm.y)) < 1.0;
}

#endif
