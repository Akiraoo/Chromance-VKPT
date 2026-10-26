#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

// Rays that leave the world: sky gradient from the sky cube, plus the sun and moon discs for rays that can see
// them sharply (camera rays, mirror-like reflections, refraction). Every other ray skips the discs because the sun
// and moon are already sampled directly at the surface it came from.

#include "lib/resources_rt.glsl"
#include "lib/payload.glsl"
#include "interface/color_space.glsl"
#include "lib/palette.glsl"
#include "lib/celestial.glsl"
#include "lib/clouds.glsl"
#include "lib/nebula.glsl"
#include "interface/random.glsl"

layout(location = 0) rayPayloadInEXT ChrRay ray;

void main() {
    ray.hitT = INF_DISTANCE;
    chrSetBit(ray, CHR_STOP_BIT, true);

    bool blocked = skyUBO.cameraSubmersionType == 0u || skyUBO.cameraSubmersionType == 2u ||
                   skyUBO.hasBlindnessOrDarkness > 0u;
    if (blocked) { return; }

    vec3 dir = normalize(gl_WorldRayDirectionEXT);
    vec3 color = vec3(0.0);
    if (worldUBO.skyType == 1u) {
        color = textureLod(chrSkyCube, dir, 0.0).rgb;
        // Light from the sky dome onto the world (rays that bounced off a rough surface) is kept well below the sky's
        // own brightness, so the sun and moon stay the main light and their shadows read clearly.
        if (!chrHasBit(ray, CHR_CAMERA_SEGMENT_BIT) && !chrHasBit(ray, CHR_SHARP_BIT)) {
            color *= clamp(float(CHR_SKY_GI_STRENGTH), 0.0, 2.0);
        }
        if (chrHasBit(ray, CHR_CAMERA_SEGMENT_BIT) || chrHasBit(ray, CHR_SHARP_BIT)) {
            ChrPalette pal = chrPalette();
            float aboveHorizon = smoothstep(-0.03, 0.01, dir.y);
            color += (chrSunDisc(pal, dir) + chrMoonDisc(pal, dir)) * aboveHorizon;
            color += chrNebula(pal, dir);
            if (CHR_CLOUD_MODE == CHR_CLOUD_MODE_VOLUMETRIC) {
                // Volumetric clouds for camera rays and mirror-like reflections (fewer samples in reflections).
                bool cameraRay = chrHasBit(ray, CHR_CAMERA_SEGMENT_BIT);
                // The sky is accumulated over frames (cloud/temporal.comp), so fewer samples per frame suffice.
                // Reflections are not accumulated by the sky TAA; per-pixel random jitter there left grainy clouds that
                // the denoiser, with its long history on calm water, smeared into a blocky mosaic. Reflections march
                // with a fixed offset and a few more steps instead: smooth, noise-free and stable.
                int steps = cameraRay ? clamp(int(float(CHR_CLOUD_STEPS) * 0.6), 8, 64) : clamp(int(CHR_CLOUD_STEPS) / 2, 8, 32);
                float jitter = 0.5;
                if (cameraRay) {
                    uint h = xxhash32(uvec3(gl_LaunchIDEXT.xy, worldUBO.seed));
                    jitter = float(h & 0xffffu) / 65536.0;
                }
                ChrCloudResult cloud = chrCloudMarch(pal, gl_WorldRayOriginEXT, dir, steps, jitter);
                // Under the rain deck the sky that peeks out below the clouds at the horizon is dim too.
                color *= mix(1.0, 0.55, chrCloudRain());
                color = color * cloud.transmittance + cloud.scatter;
                // Tell the ray generation shader how much cloud covers this sky pixel (sky pixels have no normal),
                // so stars are not drawn on top of clouds.
                if (cameraRay) { ray.normal = vec3(0.0, 1.0 - cloud.transmittance, 0.0); }
            }
        }
    } else if (worldUBO.skyType == 0u) {
        // Nether: no sky, but the hazy air still carries a little of the biome's fog colour.
        color = srgbToLinear(clamp(worldUBO.fogColor.rgb, vec3(0.0), vec3(1.0))) * 0.35;
    } else {
        // The End: faint violet void light.
        color = vec3(0.030, 0.022, 0.045);
    }
    ray.radiance += color * ray.throughput;
}
