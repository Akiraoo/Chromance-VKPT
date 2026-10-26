#ifndef CHR_RESOURCES_RT_GLSL
#define CHR_RESOURCES_RT_GLSL

// Resources bound by Radiance (MCVR) for the ray tracing stage.
//   set 0: bindless texture array
//   set 1: acceleration structure and geometry buffers
//   set 2: world / sky uniforms
//   set 5: shader pack textures (by sampled_binding / storage_binding from configs.json)

#include "common/shared.hpp"
#include "lib/settings.glsl"

layout(set = 0, binding = 0) uniform sampler2D textures[];

layout(set = 1, binding = 0) uniform accelerationStructureEXT topLevelAS;

layout(set = 1, binding = 1) readonly buffer BLASOffsets {
    uint offsets[];
}
blasOffsets;

layout(set = 1, binding = 2) readonly buffer IndexBufferAddr {
    uint64_t addrs[];
}
indexBufferAddrs;

#ifdef CHR_NEED_PREVIOUS_GEOMETRY
layout(set = 1, binding = 3) readonly buffer LastIndexBufferAddr {
    uint64_t addrs[];
}
lastIndexBufferAddrs;

layout(set = 1, binding = 8) readonly buffer LastObjToWorldMat {
    mat4 mat[];
}
lastObjToWorldMats;
#endif

layout(set = 1, binding = 7) readonly buffer TextureMappingBuffer {
    TextureMapping mapping;
};

layout(set = 2, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};

layout(set = 2, binding = 1) uniform LastWorldUniform {
    WorldUBO lastWorldUBO;
};

layout(set = 2, binding = 2) uniform SkyUniform {
    SkyUBO skyUBO;
};

#ifndef CHR_SKY_CUBE_BINDING
#    define CHR_SKY_CUBE_BINDING 2
#endif
layout(set = 5, binding = CHR_SKY_CUBE_BINDING) uniform samplerCube chrSkyCube;

layout(std430, buffer_reference, buffer_reference_align = 4) readonly buffer IndexBuffer {
    uint indices[];
}
indexBuffer;

#include "interface/vertex.glsl"

#endif
