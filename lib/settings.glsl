#ifndef CHR_SETTINGS_GLSL
#define CHR_SETTINGS_GLSL

// Fallback values for every Chromance setting. Radiance injects the real values from configs.json as
// preprocessor definitions; these only apply when a define is missing. Float settings are always read through
// float() because Radiance writes 1.0 as "1".

// Lighting
// Overall brightness of the picture (an exposure multiplier, applied before tone mapping).
#ifndef CHR_BRIGHTNESS
#    define CHR_BRIGHTNESS 0.5
#endif
// Where the border fog (hiding the far edge of the world) starts, as a fraction of the drawn distance.
#ifndef CHR_BORDER_FOG_START
#    define CHR_BORDER_FOG_START 0.92
#endif
// Metals (labPBR) reflect more sharply than their roughness map says: 0 = as the map says.
#ifndef CHR_METAL_SHARPNESS
#    define CHR_METAL_SHARPNESS 0.8
#endif
// Convert texture colours from sRGB to linear light (more contrast and colour, less washed out).
#ifndef CHR_LINEAR_TEXTURES
#    define CHR_LINEAR_TEXTURES 1
#endif
#ifndef CHR_INDIRECT_BOUNCES
#    define CHR_INDIRECT_BOUNCES 2
#endif
#ifndef CHR_SUN_STRENGTH
#    define CHR_SUN_STRENGTH 1.0
#endif
#ifndef CHR_MOON_STRENGTH
#    define CHR_MOON_STRENGTH 1.0
#endif
#ifndef CHR_BLOCK_LIGHT_SAMPLES
#    define CHR_BLOCK_LIGHT_SAMPLES 2
#endif
#ifndef CHR_LIGHT_SAMPLE_CLAMP
#    define CHR_LIGHT_SAMPLE_CLAMP 2.7
#endif
#ifndef CHR_ENTITY_LIGHT_BOOST
#    define CHR_ENTITY_LIGHT_BOOST 6.0
#endif
#ifndef CHR_NEBULA_STRENGTH
#    define CHR_NEBULA_STRENGTH 1.0
#endif
#ifndef CHR_GRADE_WARMTH
#    define CHR_GRADE_WARMTH 0.6
#endif
#ifndef CHR_GRADE_PUNCH
#    define CHR_GRADE_PUNCH 0.5
#endif
#ifndef CHR_GLASS_REFLECTION
#    define CHR_GLASS_REFLECTION 0.7
#endif
#ifndef CHR_EYE_ADAPTATION
#    define CHR_EYE_ADAPTATION 1
#endif
#ifndef CHR_EYE_ADAPTATION_STRENGTH
#    define CHR_EYE_ADAPTATION_STRENGTH 0.5
#endif
#ifndef CHR_EYE_ADAPTATION_MAX_EV
#    define CHR_EYE_ADAPTATION_MAX_EV 0.75
#endif
#ifndef CHR_EYE_ADAPTATION_SPEED
#    define CHR_EYE_ADAPTATION_SPEED 1.0
#endif
#ifndef CHR_SKY_GI_STRENGTH
#    define CHR_SKY_GI_STRENGTH 0.4
#endif
#ifndef CHR_AIR_GOD_RAYS
#    define CHR_AIR_GOD_RAYS 0.5
#endif
#ifndef CHR_SKY_LIGHT_STRENGTH
#    define CHR_SKY_LIGHT_STRENGTH 1.0
#endif
#ifndef CHR_SUN_SOFTNESS
#    define CHR_SUN_SOFTNESS 1.0
#endif
#ifndef CHR_MINIMUM_LIGHT
#    define CHR_MINIMUM_LIGHT 0.0004
#endif
#ifndef CHR_INDIRECT_CLAMP
#    define CHR_INDIRECT_CLAMP 4.0
#endif

// Block lights (emissive surfaces)
#ifndef CHR_BLOCK_LIGHT_STRENGTH
#    define CHR_BLOCK_LIGHT_STRENGTH 10.0
#endif
#ifndef CHR_BLOCK_LIGHT_RANGE
#    define CHR_BLOCK_LIGHT_RANGE 12.0
#endif
#ifndef CHR_WEAK_EMITTER_LIGHT
#    define CHR_WEAK_EMITTER_LIGHT 0.0
#endif
#ifndef CHR_BLOCK_LIGHT_CANDIDATES
#    define CHR_BLOCK_LIGHT_CANDIDATES 6
#endif
#ifndef CHR_BLOCK_LIGHT_BOUNCES
#    define CHR_BLOCK_LIGHT_BOUNCES 2
#endif
#ifndef CHR_EMISSIVE_BRIGHTNESS
#    define CHR_EMISSIVE_BRIGHTNESS 2.0
#endif

// Sky and time of day
#ifndef CHR_CELESTIAL_SHAPE
#    define CHR_CELESTIAL_SHAPE 0u
#endif
#ifndef CHR_SUN_SIZE
#    define CHR_SUN_SIZE 1.0
#endif
#ifndef CHR_MOON_SIZE
#    define CHR_MOON_SIZE 1.0
#endif
#ifndef CHR_GOLDEN_HOUR_STRENGTH
#    define CHR_GOLDEN_HOUR_STRENGTH 1.0
#endif
#ifndef CHR_BLUE_HOUR_STRENGTH
#    define CHR_BLUE_HOUR_STRENGTH 1.0
#endif
#ifndef CHR_NIGHT_BRIGHTNESS
#    define CHR_NIGHT_BRIGHTNESS 0.3
#endif
#ifndef CHR_NIGHT_DESATURATION
#    define CHR_NIGHT_DESATURATION 0.75
#endif

// Atmosphere and fog
#ifndef CHR_FOG_DENSITY
#    define CHR_FOG_DENSITY 1.0
#endif
#ifndef CHR_WATER_FOG_DENSITY
#    define CHR_WATER_FOG_DENSITY 0.75
#endif

// Materials
#ifndef CHR_PBR_FILTER
#    define CHR_PBR_FILTER 0u
#endif
#ifndef CHR_NORMAL_MAP_STRENGTH
#    define CHR_NORMAL_MAP_STRENGTH 1.0
#endif
#ifndef CHR_WATER_WAVE_OVERLAY
#    define CHR_WATER_WAVE_OVERLAY 1
#endif
// Water surface seen from below: 0 real (Snell's window), 1 mirror (sharp window, no partial reflection), 2 clear.
#ifndef CHR_WATER_SNELL_WINDOW
#    define CHR_WATER_SNELL_WINDOW 0u
#endif
#ifndef CHR_WATER_WAVE_OVERLAY_STRENGTH
#    define CHR_WATER_WAVE_OVERLAY_STRENGTH 1.0
#endif
#ifndef CHR_WATER_BIOME_TINT
#    define CHR_WATER_BIOME_TINT 0.6
#endif
#ifndef CHR_WATER_GOD_RAYS
#    define CHR_WATER_GOD_RAYS 0.2
#endif
#ifndef CHR_WATER_WAVE_STRENGTH
#    define CHR_WATER_WAVE_STRENGTH 0.0
#endif
#ifndef CHR_CLOUD_MODE
#    define CHR_CLOUD_MODE 1u
#endif

const uint CHR_CLOUD_MODE_OFF = 0u;
const uint CHR_CLOUD_MODE_BLOCK = 1u;
const uint CHR_CLOUD_MODE_VOLUMETRIC = 2u;

#ifndef CHR_CLOUD_COVERAGE
#    define CHR_CLOUD_COVERAGE 0.45
#endif
#ifndef CHR_CLOUD_STEPS
#    define CHR_CLOUD_STEPS 32
#endif
#ifndef CHR_CLOUD_SHADOW_STRENGTH
#    define CHR_CLOUD_SHADOW_STRENGTH 0.45
#endif

const uint CHR_SHAPE_ROUND = 0u;
const uint CHR_SHAPE_SQUARE = 1u;

#endif

// Overall scale of glowing surfaces (torch flames, lava, glowstone...) on top of the Emissive Brightness setting: the
// glowing blocks themselves were blowing out to white. world.rgen and world/surface_impl.glsl must use the same
// value (the denoiser is given the emission separately and subtracts it).
const float CHR_EMISSIVE_SCALE = 0.65;
// Overall scale of the light block lights throw on their surroundings, on top of the Block Light Strength setting.
const float CHR_BLOCK_LIGHT_SCALE = 0.75;
