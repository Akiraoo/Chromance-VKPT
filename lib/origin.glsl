#ifndef CHR_ORIGIN_GLSL
#define CHR_ORIGIN_GLSL

// Far from the world origin a 32-bit float cannot hold an absolute block coordinate precisely: at 1,000,000 blocks
// its step is 1/16 block (one texture pixel), at 10,000,000 a whole block. Everything world-anchored that the pack
// draws (waves, rain ripples, caustics, clouds) used absolute = relative + float(cameraPos), so out there it broke
// into a grid of flat squares. The camera position arrives in double precision; wrap it here, in doubles, into a
// 16384-block repeat before going to floats. The patterns repeat every 16384 blocks (a seam once per 16384 blocks
// is far better than a mosaic everywhere). The repeat is centred on the origin, so the seams sit at +-8192,
// +-24576, ... and never at 0, where players cross most often. Y is left as it is.

const double CHR_ORIGIN_PERIOD = 16384.0;

// Camera position, X and Z wrapped into [-8192, 8192), as a float. absolute (wrapped) = relative + this.
vec3 chrWrappedCamera(dvec3 c) {
    dvec2 xz = c.xz - floor((c.xz + CHR_ORIGIN_PERIOD * 0.5) / CHR_ORIGIN_PERIOD) * CHR_ORIGIN_PERIOD;
    return vec3(float(xz.x), float(c.y), float(xz.y));
}

// Integer block column of a camera-relative position, wrapped into [0, 65536): stable for per-column hashes.
vec2 chrWrappedColumn(vec2 rel, dvec2 cameraXZ) {
    dvec2 a = floor(dvec2(rel) + cameraXZ);
    a -= floor(a / 65536.0) * 65536.0;
    return vec2(a);
}

#endif
