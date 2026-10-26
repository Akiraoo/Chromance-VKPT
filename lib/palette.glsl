#ifndef CHR_PALETTE_GLSL
#define CHR_PALETTE_GLSL

// Time-of-day palette. Everything that gives the picture its mood comes from here: the colour and strength of
// the sun and moon, the sky gradient, the horizon glow and the fog tint.
//
//   noon        white sun, deep blue zenith, bright pale horizon
//   golden hour low sun, warm gold light, orange horizon on the sun side
//   blue hour   sun just below the horizon, no direct light, pale blue sky
//   night       dim, almost neutral moonlight and a dark grey-blue sky (not an all-blue world)
//
// Requires skyUBO / worldUBO and lib/settings.glsl.

#include "lib/brdf.glsl"

// Sun path tilted 10 degrees toward the south so noon shadows are not perfectly vertical.
vec3 chrTiltSouth(vec3 d) {
    const float s = 0.17364817766693033;
    const float c = 0.984807753012208;
    return chrSafeNormalize(vec3(d.x, d.y * c - d.z * s, d.y * s + d.z * c), vec3(0.0, 1.0, 0.0));
}

vec3 chrSunDirection() {
    return chrTiltSouth(chrSafeNormalize(skyUBO.sunDirection, vec3(0.0, 1.0, 0.0)));
}

vec3 chrMoonDirection() {
    return -chrSunDirection();
}

// Radiance cannot lower exposure below 0 EV, so daylight has to land near its metering target (~0.8) by
// itself; brighter values simply clip and wash the picture out.
const float CHR_SUN_INTENSITY = 0.9;

struct ChrPalette {
    vec3 sunDir;        // direction to the sun
    vec3 lightDir;      // direction of the active directional light (sun by day, moon by night)
    vec3 lightColor;    // radiance of the active directional light, zero around the horizon crossing
    vec3 sunRadiance;   // sun light colour (for the visible disc)
    vec3 moonRadiance;  // moon light colour (for the visible disc)
    vec3 zenith;
    vec3 horizon;       // horizon away from the sun
    vec3 horizonSun;    // horizon on the sun side
    vec3 glow;          // halo around the sun
    float day;          // 0 at night, 1 by day
    float golden;       // golden hour weight
    float blue;         // blue hour weight
    float night;        // night weight
    float rain;
};

vec3 chrDesaturate(vec3 c, float amount) {
    return mix(c, vec3(chrLuminance(c)), clamp(amount, 0.0, 1.0));
}

// Moon brightness by phase: 0 = full moon ... 4 = new moon.
float chrMoonPhaseBrightness(uint phase) {
    float p = float(phase % 8u);
    float fromFull = min(p, 8.0 - p) / 4.0;
    return mix(1.0, 0.18, fromFull);
}

ChrPalette chrPalette() {
    ChrPalette p;
    p.sunDir = chrSunDirection();
    float e = p.sunDir.y;
    p.rain = clamp(skyUBO.rainGradient, 0.0, 1.0);

    float goldenStrength = max(float(CHR_GOLDEN_HOUR_STRENGTH), 0.0);
    float blueStrength = max(float(CHR_BLUE_HOUR_STRENGTH), 0.0);
    float nightBrightness = max(float(CHR_NIGHT_BRIGHTNESS), 0.0);
    float nightDesat = clamp(float(CHR_NIGHT_DESATURATION), 0.0, 1.0);

    p.day = smoothstep(-0.04, 0.10, e);
    p.golden = smoothstep(-0.05, 0.02, e) * (1.0 - smoothstep(0.10, 0.34, e));
    p.blue = smoothstep(-0.24, -0.10, e) * (1.0 - smoothstep(-0.06, 0.0, e));
    p.night = 1.0 - smoothstep(-0.26, -0.10, e);

    // ---- Sun -----------------------------------------------------------------------------------------------
    vec3 noonSun = vec3(1.0, 0.94, 0.84);   // warm daylight, like late-morning sun
    vec3 lowSun = mix(vec3(1.0, 0.38, 0.12), vec3(1.0, 0.62, 0.32), smoothstep(0.0, 0.16, e));
    vec3 sunTint = mix(noonSun, lowSun, clamp(p.golden * goldenStrength, 0.0, 1.0) * (1.0 - smoothstep(0.16, 0.42, e)));
    // Like a scene light in a game engine: the shadow-casting light follows the sun by day and the moon by night,
    // keeps casting clear shadows right down to sunrise / sunset, and only dips briefly at the horizon where it
    // switches between the two.
    float sunHeight = smoothstep(-0.005, 0.035, e) * mix(0.6, 1.0, smoothstep(0.05, 0.45, e));
    p.sunRadiance = sunTint * CHR_SUN_INTENSITY * sunHeight * max(float(CHR_SUN_STRENGTH), 0.0);

    // ---- Moon ----------------------------------------------------------------------------------------------
    float moonE = -e;
    vec3 moonTint = chrDesaturate(vec3(0.70, 0.80, 1.0), nightDesat);
    // A low moon gives almost no light, so hills facing it do not light up oddly in the distance.
    float moonHeight = smoothstep(-0.005, 0.06, moonE) * mix(0.6, 1.0, smoothstep(0.05, 0.40, moonE));
    p.moonRadiance = moonTint * 0.018 * moonHeight * chrMoonPhaseBrightness(skyUBO.moonPhase) * nightBrightness *
                     max(float(CHR_MOON_STRENGTH), 0.0);

    // Only one shadow-casting light at a time; both fade to zero at the horizon so the switch is invisible.
    bool sunUp = e >= 0.0;
    p.lightDir = sunUp ? p.sunDir : -p.sunDir;
    p.lightColor = sunUp ? p.sunRadiance : p.moonRadiance;
    // Overcast: the sun is mostly hidden and its light becomes flat sky light.
    p.lightColor *= mix(1.0, 0.03, p.rain);

    // ---- Sky gradient --------------------------------------------------------------------------------------
    // Deep blue overhead fading to a warm, creamy horizon (warmest on the sun's side).
    vec3 dayZenith = vec3(0.13, 0.31, 0.92) * 0.62;
    vec3 dayHorizon = vec3(0.76, 0.83, 0.95) * 0.60;
    vec3 dayHorizonSun = vec3(0.95, 0.90, 0.84) * 0.64;

    // Golden hour: the whole sky warms, not only the sun's side (peach away from the sun, amber towards it).
    vec3 goldZenith = vec3(0.34, 0.38, 0.62) * 0.55;
    vec3 goldHorizonSun = vec3(1.00, 0.58, 0.28) * 0.90;
    vec3 goldHorizon = vec3(0.92, 0.66, 0.52) * 0.50;

    vec3 blueZenith = vec3(0.12, 0.20, 0.46) * 0.16;
    vec3 blueHorizon = vec3(0.46, 0.60, 0.88) * 0.18;
    vec3 blueHorizonSun = vec3(0.80, 0.58, 0.62) * 0.19;

    vec3 nightZenith = chrDesaturate(vec3(0.0034, 0.0044, 0.0072), nightDesat) * nightBrightness;
    vec3 nightHorizon = chrDesaturate(vec3(0.0044, 0.0052, 0.0076), nightDesat) * nightBrightness;

    float dayOnly = clamp(p.day - p.golden * goldenStrength * 0.85, 0.0, 1.0);
    float gold = clamp(p.golden * goldenStrength, 0.0, 1.0);
    float blue = p.blue * blueStrength;

    // Weighted blend of the four looks. Weights overlap smoothly so no phase pops.
    vec4 w = vec4(dayOnly, gold, blue, p.night);
    float wSum = max(w.x + w.y + w.z + w.w, 1e-3);
    w /= wSum;
    p.zenith = dayZenith * w.x + goldZenith * w.y + blueZenith * w.z + nightZenith * w.w;
    p.horizon = dayHorizon * w.x + goldHorizon * w.y + blueHorizon * w.z + nightHorizon * w.w;
    p.horizonSun = dayHorizonSun * w.x + goldHorizonSun * w.y + blueHorizonSun * w.z + nightHorizon * w.w;
    p.glow = mix(vec3(1.0, 0.86, 0.66) * 0.7, vec3(1.0, 0.55, 0.22) * 1.6, clamp(gold + blue * 0.3, 0.0, 1.0)) *
             smoothstep(-0.12, 0.02, e);

    // Rain: flat grey overcast, darker at night.
    // Values are absolute: Chromance expects Radiance's manual exposure at 0 EV with no curve lift (see README),
    // so what is written here is what ends up on screen.
    float overcastLevel = mix(0.0035, 0.09, p.day) * mix(1.0, 0.7, p.golden);
    vec3 overcast = vec3(0.70, 0.76, 0.86) * overcastLevel;
    p.zenith = mix(p.zenith, overcast * 0.85, p.rain);
    p.horizon = mix(p.horizon, overcast, p.rain);
    p.horizonSun = mix(p.horizonSun, overcast * 1.08, p.rain);
    p.glow *= 1.0 - p.rain * 0.85;

    float skyScale = max(float(CHR_SKY_LIGHT_STRENGTH), 0.0);
    p.zenith *= skyScale;
    p.horizon *= skyScale;
    p.horizonSun *= skyScale;
    return p;
}

// Sky radiance without sun and moon discs.
vec3 chrSkyRadiance(ChrPalette p, vec3 dir) {
    float h = dir.y;
    vec2 sunXZ = p.sunDir.xz;
    float sunXZLen = length(sunXZ);
    float sunSide = 0.5;
    vec2 dirXZ = dir.xz;
    float dirXZLen = length(dirXZ);
    if (sunXZLen > 1e-4 && dirXZLen > 1e-4) { sunSide = dot(dirXZ / dirXZLen, sunXZ / sunXZLen) * 0.5 + 0.5; }
    sunSide = sunSide * sunSide * sunSide;

    vec3 horizon = mix(p.horizon, p.horizonSun, sunSide);
    // One smooth curve across the horizon (no kink at h = 0, which showed up as a bright band).
    float horizonBlend = exp(-max(h, 0.0) * 4.0);
    vec3 sky = mix(p.zenith, horizon, horizonBlend);

    // Halo around the sun: wide soft part plus a tighter bright core.
    float mu = max(dot(dir, p.sunDir), 0.0);
    float halo = pow(mu, 6.0) * 0.35 + pow(mu, 48.0) * 0.9;
    sky += p.glow * halo * (0.4 + 0.6 * horizonBlend);

    // Below the horizon fade gently toward a darker ground colour so reflections of the void do not glow.
    sky = mix(sky, horizon * 0.4, smoothstep(0.02, -0.45, h));
    return max(sky, vec3(0.0));
}

// Colour the distance fog fades into for a view direction. The bright halo around the sun is left out: that light
// comes straight from the sun and can be blocked (it is added by the occlusion-tested sun shafts instead), so a
// mountain in front of the setting sun stays a dark silhouette rather than glowing orange.
vec3 chrFogColor(ChrPalette p, vec3 dir) {
    vec3 flatDir = chrSafeNormalize(vec3(dir.x, max(dir.y, 0.0) * 0.35, dir.z), vec3(1.0, 0.0, 0.0));
    vec3 glow = p.glow;
    p.glow = vec3(0.0);
    vec3 fog = chrSkyRadiance(p, flatDir);
    // Keep only a faint, wide warm tint towards the sun.
    float mu = max(dot(flatDir, p.sunDir), 0.0);
    fog += glow * pow(mu, 4.0) * 0.08;
    // Under a rain deck little light reaches the air near the ground: keep distant land grey, not glowing white.
    return fog * mix(1.0, 0.5, p.rain);
}

#endif
