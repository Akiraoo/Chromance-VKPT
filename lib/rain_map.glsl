#ifndef CHR_RAIN_MAP_GLSL
#define CHR_RAIN_MAP_GLSL

// Radiance's rain map (SkyUBO.rainData): a 512 x 512 texture around the player, one texel per block column.
//   r + 256 g - 32768 : highest block that stops rain in this column
//   b                 : 255 if the column's biome gets rain (0 in deserts, savannas, snowy places, ...)
//   a                 : 0 if the column has no data
// The upper 16 bits of rainData hold a wetness value that follows the rain within a few seconds and dries out over
// about 25 seconds after it stops. Requires lib/resources_rt.glsl.

struct ChrRainMap {
    bool available;  // false: Radiance sent no rain map, fall back to sky light
    float exposure;  // 0..1, this point is out in the rain (and its biome gets rain)
    float wetness;   // 0..1, slowly drying wetness of the ground
};

ivec4 chrRainColumn(uint textureId, ivec2 column) {
    return ivec4(round(texelFetch(textures[nonuniformEXT(textureId)], column & ivec2(511), 0) * 255.0));
}

bool chrRainColumnBlocked(ivec4 data, int surfaceBlockY) {
    return data.a == 0 || (data.r + 256 * data.g - 32768) > surfaceBlockY;
}

// position: camera-relative hit position (absolute = position + cameraPos), up: geometric normal's y.
ChrRainMap chrRainMap(vec3 position, float up) {
    ChrRainMap m;
    uint textureId = skyUBO.rainData & 65535u;
    m.available = textureId != 0u;
    m.exposure = 0.0;
    m.wetness = float(skyUBO.rainData >> 16u) / 65535.0;
    if (!m.available) { return m; }
    if (max(abs(position.x), abs(position.z)) > 238.0) { return m; }

    ivec3 cameraCell = ivec3(floor(worldUBO.cameraPos.xyz));
    vec3 rel = position + vec3(worldUBO.cameraPos.xyz - dvec3(cameraCell));
    ivec2 column = cameraCell.xz + ivec2(floor(rel.xz));
    // Top faces belong to the block below them; side faces to their own block.
    int surfaceBlockY = cameraCell.y + int(floor(rel.y - (up > 0.5 ? 0.001 : -0.001)));
    ivec4 centre = chrRainColumn(textureId, column);
    if (chrRainColumnBlocked(centre, surfaceBlockY)) { return m; }
    // Whether the biome gets rain changes in 4 x 4 block steps (Minecraft's biome grid), which left hard-edged dry
    // rectangles in wet ground at biome borders (a beach next to a desert). Blend it over a few blocks instead:
    // the share of rainy columns in a ring around the point, so wet ground fades out gradually.
    float rainyBiome = centre.b > 0 ? 1.0 : 0.0;
    const ivec2 ring[8] = ivec2[](ivec2(3, 0), ivec2(-3, 0), ivec2(0, 3), ivec2(0, -3),
                                  ivec2(2, 2), ivec2(-2, 2), ivec2(2, -2), ivec2(-2, -2));
    for (int i = 0; i < 8; ++i) {
        rainyBiome += chrRainColumn(textureId, column + ring[i]).b > 0 ? 1.0 : 0.0;
    }
    rainyBiome = smoothstep(0.15, 0.85, rainyBiome / 9.0);
    if (rainyBiome <= 0.0) { return m; }

    // Soften the edge towards covered neighbours so roof edges do not cut a hard line.
    vec2 within = fract(rel.xz);
    ivec2 side = ivec2(step(vec2(0.5), within)) * 2 - 1;
    vec2 edge = min(within, vec2(1.0) - within);
    float edge2 = 0.25;
    if (chrRainColumnBlocked(chrRainColumn(textureId, column + ivec2(side.x, 0)), surfaceBlockY)) {
        edge2 = min(edge2, edge.x * edge.x);
    }
    if (chrRainColumnBlocked(chrRainColumn(textureId, column + ivec2(0, side.y)), surfaceBlockY)) {
        edge2 = min(edge2, edge.y * edge.y);
    }
    if (chrRainColumnBlocked(chrRainColumn(textureId, column + side), surfaceBlockY)) {
        edge2 = min(edge2, dot(edge, edge));
    }
    m.exposure = smoothstep(0.0, 0.5, sqrt(edge2)) * rainyBiome * (1.0 - smoothstep(220.0, 238.0, max(abs(position.x), abs(position.z))));
    return m;
}

#endif
