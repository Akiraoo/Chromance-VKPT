#ifndef CHR_NEBULA_GLSL
#define CHR_NEBULA_GLSL

// A faint, coloured nebula band across the night sky (a stylised Milky Way): soft clouds of violet, blue, teal
// and a little rose, crossed by darker dust lanes. It turns with the stars (the sky rotates about the same axis
// as the sun and moon) and fades out at dusk, in the rain and near the horizon. Its texture also hides the 8-bit
// banding that a perfectly smooth dark sky shows. Requires lib/palette.glsl, lib/settings.glsl.

float chrNebHash(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float chrNebNoise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(chrNebHash(i), chrNebHash(i + vec3(1, 0, 0)), f.x),
                   mix(chrNebHash(i + vec3(0, 1, 0)), chrNebHash(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(chrNebHash(i + vec3(0, 0, 1)), chrNebHash(i + vec3(1, 0, 1)), f.x),
                   mix(chrNebHash(i + vec3(0, 1, 1)), chrNebHash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float chrNebFbm(vec3 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; ++i) {
        v += chrNebNoise(p) * a;
        p = p * 2.03 + vec3(1.7, 9.2, 4.1);
        a *= 0.5;
    }
    return v;
}

vec3 chrNebula(ChrPalette pal, vec3 dir) {
    float amount = max(float(CHR_NEBULA_STRENGTH), 0.0);
    float visible = pal.night * (1.0 - pal.rain) * smoothstep(-0.02, 0.25, dir.y);
    if (amount <= 0.0 || visible <= 0.0) { return vec3(0.0); }

    // Fixed sky frame: undo the daily rotation (the sun turns about the Z axis).
    float angle = atan(pal.sunDir.y, pal.sunDir.x);
    float c = cos(-angle), s = sin(-angle);
    vec3 d = vec3(c * dir.x - s * dir.y, s * dir.x + c * dir.y, dir.z);

    // The band: a great circle tilted against the sky's rotation axis, widened and wobbled by noise.
    vec3 bandNormal = normalize(vec3(0.35, 0.55, 0.76));
    float warp = chrNebFbm(d * 2.2) - 0.5;
    float band = exp(-pow(dot(d, bandNormal) + warp * 0.35, 2.0) * 9.0);

    float cloud = chrNebFbm(d * 3.5 + vec3(3.0));
    float wisps = chrNebFbm(d * 9.0 + vec3(11.0));
    float dust = smoothstep(0.45, 0.7, chrNebFbm(d * 6.0 + vec3(23.0)));
    float density = band * smoothstep(0.35, 0.85, cloud * 0.75 + wisps * 0.35) * (1.0 - dust * 0.75);

    // Colour drifts along the band.
    float hue = chrNebFbm(d * 1.4 + vec3(7.0));
    vec3 violet = vec3(0.55, 0.30, 1.00);
    vec3 blue = vec3(0.25, 0.45, 1.00);
    vec3 teal = vec3(0.20, 0.85, 0.80);
    vec3 rose = vec3(1.00, 0.35, 0.60);
    vec3 col = mix(mix(blue, violet, smoothstep(0.35, 0.55, hue)), mix(teal, rose, smoothstep(0.45, 0.7, hue)),
                   smoothstep(0.5, 0.65, hue));
    // A soft glow in the band's core.
    vec3 core = vec3(0.85, 0.80, 1.0) * band * band * 0.25 * cloud;
    float brightness = 0.0035 * max(float(CHR_NIGHT_BRIGHTNESS), 0.0) / 0.3;
    return (col * density + core) * brightness * visible * amount;
}

#endif
