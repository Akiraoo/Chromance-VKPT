#ifndef CHR_END_PORTAL_GLSL
#    define CHR_END_PORTAL_GLSL

// End portal / gateway starfield, derived from the Vanilla PT shader pack (GPL-3.0).
const vec3[] CHR_COLORS = vec3[](vec3(0.022087, 0.098399, 0.110818),
                                 vec3(0.011892, 0.095924, 0.089485),
                                 vec3(0.027636, 0.101689, 0.100326),
                                 vec3(0.046564, 0.109883, 0.114838),
                                 vec3(0.064901, 0.117696, 0.097189),
                                 vec3(0.063761, 0.086895, 0.123646),
                                 vec3(0.084817, 0.111994, 0.166380),
                                 vec3(0.097489, 0.154120, 0.091064),
                                 vec3(0.106152, 0.131144, 0.195191),
                                 vec3(0.097721, 0.110188, 0.187229),
                                 vec3(0.133516, 0.138278, 0.148582),
                                 vec3(0.070006, 0.243332, 0.235792),
                                 vec3(0.196766, 0.142899, 0.214696),
                                 vec3(0.047281, 0.315338, 0.321970),
                                 vec3(0.204675, 0.390010, 0.302066),
                                 vec3(0.080955, 0.314821, 0.661491));
const mat4 CHR_SCALE_TRANSLATE = mat4(0.5, 0.0, 0.0, 0.25, 0.0, 0.5, 0.0, 0.25, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0);


vec4 projectPosition(vec4 position) {
    vec4 projection = position * 0.5;
    projection.xy = vec2(projection.x + projection.w, projection.y + projection.w);
    projection.zw = position.zw;
    return projection;
}


vec3 computeEndPortalColor(
    vec4 texProj0, int iterations, uint endSkyTextureID, uint endPortalTextureID, float gameTime) {
    vec3 color = vec3(0.0);
    if (endSkyTextureID != 0xFFFFFFFFu)
        color += textureProj(textures[nonuniformEXT(endSkyTextureID)], texProj0).rgb * CHR_COLORS[0];
    for (int i = 0; i < iterations; i++) {
        if (endPortalTextureID != 0xFFFFFFFFu) {
            float layer = float(i + 1);
            mat4 translate = mat4(1.0, 0.0, 0.0, 17.0 / layer, 0.0, 1.0, 0.0, (2.0 + layer / 1.5) * (gameTime * 1.5),
                                  0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
            float rotationAngle = radians((layer * layer * 4321.0 + layer * 9.0) * 2.0);
            mat2 rotate = mat2(cos(rotationAngle), -sin(rotationAngle), sin(rotationAngle), cos(rotationAngle));
            mat2 scale = mat2((4.5 - layer / 4.0) * 2.0);
            mat4 portalLayer = mat4(scale * rotate) * translate * CHR_SCALE_TRANSLATE;
            color +=
                textureProj(textures[nonuniformEXT(endPortalTextureID)], texProj0 * portalLayer).rgb * CHR_COLORS[i];
        }
    }
    return color;
}
#endif
