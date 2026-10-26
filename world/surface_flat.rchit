#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

// Entity layers Radiance draws with a forward depth offset: same shading as surface.rchit but without normal
// maps, which tend to shimmer on these thin offset layers.
#define CHR_FLAT_SURFACE 1
#include "world/surface_impl.glsl"
