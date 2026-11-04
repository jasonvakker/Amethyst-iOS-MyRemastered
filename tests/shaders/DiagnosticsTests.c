#include <assert.h>
#include <unistd.h>
#include "diag-production.h"

static const VkShaderModuleCreateInfo *expected_shader_info;
static const VkAllocationCallbacks *expected_allocator;
static const VkCommandBufferBeginInfo *expected_begin_info;
static VkResult mock_result;
static VkResult VKAPI_CALL create_shader(VkDevice device, const VkShaderModuleCreateInfo *info,
    const VkAllocationCallbacks *allocator, VkShaderModule *module) {
    assert(device == (VkDevice)(uintptr_t)3);
    assert(info == expected_shader_info && allocator == expected_allocator);
    if (mock_result == VK_SUCCESS) *module = (VkShaderModule)(uintptr_t)5;
    return mock_result;
}
static VkResult VKAPI_CALL begin_command(VkCommandBuffer command, const VkCommandBufferBeginInfo *info) {
    assert(command == (VkCommandBuffer)(uintptr_t)7 && info == expected_begin_info);
    return mock_result;
}
static void *failure_worker(void *context) {
    const VkGraphicsPipelineCreateInfo *pipeline = context;
    for (int i = 0; i < 20; ++i) ame_sd_failure(1, pipeline, VK_ERROR_INITIALIZATION_FAILED);
    return NULL;
}
int main(int argc, char **argv) {
    assert(argc == 2);
    int enabled = strcmp(argv[1], "enabled") == 0;
    assert(ame_sd_enabled() == enabled);
    assert(!strcmp(ame_sd_format((VkFormat)82), "R16G16_SINT"));
    assert(!strcmp(ame_sd_format((VkFormat)83), "R16G16_SFLOAT"));
    assert(!strcmp(ame_sd_format((VkFormat)88), "R16G16B16_UINT"));
    assert(!strcmp(ame_sd_format((VkFormat)100), "R32_SFLOAT"));
    assert(!strcmp(ame_sd_format((VkFormat)101), "R32G32_UINT"));

    uint32_t words[] = {0x07230203, 0x00010000, 0, 1, 0};
    VkShaderModuleCreateInfo shader = {.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                                     .codeSize=sizeof(words), .pCode=words};
    VkShaderModule module = VK_NULL_HANDLE;
    expected_shader_info = &shader;
    expected_allocator = (const VkAllocationCallbacks *)(uintptr_t)9;
    PFN_vkCreateShaderModule create = (PFN_vkCreateShaderModule)
        amethyst_diag_resolve("vkCreateShaderModule", (void *)create_shader);
    mock_result = VK_ERROR_OUT_OF_HOST_MEMORY;
    assert(create((VkDevice)(uintptr_t)3, &shader, expected_allocator, &module) == mock_result);
    assert(ame_sd_module_serial == 0);
    mock_result = VK_SUCCESS;
    assert(create((VkDevice)(uintptr_t)3, &shader, expected_allocator, &module) == VK_SUCCESS);
    assert(module == (VkShaderModule)(uintptr_t)5);
    assert(ame_sd_module_serial == (unsigned)enabled);
    assert(amethyst_diag_extra_proc("vkCreateShaderModule") == enabled);
    assert(amethyst_diag_extra_proc("vkBeginCommandBuffer") == enabled);
    assert(!amethyst_diag_extra_proc("vkCreateGraphicsPipelines"));
    assert(!amethyst_diag_extra_proc(NULL));
    assert(!amethyst_diag_resolve("vkCreateShaderModule", NULL));

    VkCommandBufferBeginInfo begin = {.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    expected_begin_info = &begin;
    PFN_vkBeginCommandBuffer begin_fn = (PFN_vkBeginCommandBuffer)
        amethyst_diag_resolve("vkBeginCommandBuffer", (void *)begin_command);
    mock_result = VK_ERROR_OUT_OF_HOST_MEMORY;
    assert(begin_fn((VkCommandBuffer)(uintptr_t)7, &begin) == mock_result);
    mock_result = VK_SUCCESS;
    assert(begin_fn((VkCommandBuffer)(uintptr_t)7, &begin) == VK_SUCCESS);

    VkVertexInputBindingDescription binding = {.binding=1, .stride=54};
    VkVertexInputAttributeDescription attrs[] = {
        {.location=3, .binding=1, .format=(VkFormat)82, .offset=24},
        {.location=8, .binding=1, .format=(VkFormat)88, .offset=36},
        {.location=9, .binding=1, .format=(VkFormat)100, .offset=42}};
    VkVertexInputAttributeDescription before[3];
    memcpy(before, attrs, sizeof(attrs));
    VkPipelineVertexInputStateCreateInfo vertex = {.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount=1, .pVertexBindingDescriptions=&binding,
        .vertexAttributeDescriptionCount=3, .pVertexAttributeDescriptions=attrs};
    VkPipelineShaderStageCreateInfo stage = {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage=VK_SHADER_STAGE_VERTEX_BIT, .module=module, .pName="main"};
    VkGraphicsPipelineCreateInfo pipeline = {.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount=1, .pStages=&stage, .pVertexInputState=&vertex};
    assert(ame_sd_failure(1, &pipeline, VK_ERROR_INITIALIZATION_FAILED) == (unsigned)enabled);
    assert(!memcmp(attrs, before, sizeof(attrs)) && binding.stride == 54);
    ame_sd_begin((VkCommandBuffer)(uintptr_t)7);
    ame_sd_bind((VkCommandBuffer)(uintptr_t)7, (VkPipeline)(uintptr_t)11);
    ame_sd_begin((VkCommandBuffer)(uintptr_t)8);
    ame_sd_bind((VkCommandBuffer)(uintptr_t)8, (VkPipeline)(uintptr_t)0xdead0001);
    for (int i=0; i<4096; ++i)
        ame_sd_skip((VkCommandBuffer)(uintptr_t)7, (VkPipeline)(uintptr_t)0xdead0001, "indexed");
    if (enabled) {
        unsigned slot = ame_sd_command_slot((VkCommandBuffer)(uintptr_t)7);
        assert(ame_sd_commands[slot].pipeline == (VkPipeline)(uintptr_t)11);
        assert(ame_sd_commands[slot].skips == 4096);
        ame_sd_begin((VkCommandBuffer)(uintptr_t)7);
        assert(!ame_sd_commands[slot].pipeline && ame_sd_commands[slot].began);
        pthread_t workers[2];
        for (int i=0;i<2;++i) assert(!pthread_create(workers+i, NULL, failure_worker, &pipeline));
        for (int i=0;i<2;++i) assert(!pthread_join(workers[i], NULL));
        assert(ame_sd_failure_serial == 41);
        // Exceed byte budget without reading the fake oversized payload.
        shader.codeSize = AME_SD_BYTES + 1;
        ame_sd_shader((VkShaderModule)(uintptr_t)6, &shader);
        assert(ame_sd_saved_modules == 1 && ame_sd_written_bytes == sizeof(words));
    } else {
        assert(ame_sd_failure_serial == 0 && ame_sd_saved_modules == 0);
    }
    puts(enabled ? "PASS: diagnostics preserve forwarding/data, identify formats, track command buffers and bound output" :
                   "PASS: disabled diagnostics record no shaders, failures or commands");
    return 0;
}
