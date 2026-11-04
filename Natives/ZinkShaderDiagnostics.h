#ifndef AMETHYST_ZINK_SHADER_DIAGNOSTICS_H
#define AMETHYST_ZINK_SHADER_DIAGNOSTICS_H

// Observational only: no Vulkan/GL calls, descriptor edits, or GPU readbacks.
#include <vulkan/vulkan_core.h>
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#ifndef AMETHYST_SHADER_DIAG_BUILD
#define AMETHYST_SHADER_DIAG_BUILD 0
#endif
#define AME_SD_MODULES 512
#define AME_SD_COMMANDS 64
#define AME_SD_FAILURES 32
#define AME_SD_BYTES (16u * 1024u * 1024u)

static pthread_once_t ame_sd_once = PTHREAD_ONCE_INIT;
static pthread_mutex_t ame_sd_mutex = PTHREAD_MUTEX_INITIALIZER;
static int ame_sd_on;
static char ame_sd_directory[1024];
static uint64_t ame_sd_module_serial, ame_sd_failure_serial;
static size_t ame_sd_written_bytes;
static unsigned ame_sd_saved_modules;
static struct { VkShaderModule handle; uint64_t serial; } ame_sd_modules[AME_SD_MODULES];
static struct {
    VkCommandBuffer command;
    VkPipeline pipeline;
    uint64_t skips;
    int began;
} ame_sd_commands[AME_SD_COMMANDS];

static inline void ame_sd_init(void) {
    const char *flag = getenv("AMETHYST_SHADER_DIAG");
    ame_sd_on = flag ? strcmp(flag, "1") == 0 : AMETHYST_SHADER_DIAG_BUILD;
    if (!ame_sd_on) return;
    const char *directory = getenv("AMETHYST_SHADER_DIAG_DIR");
    int length;
    if (directory && *directory) {
        length = snprintf(ame_sd_directory, sizeof(ame_sd_directory), "%s", directory);
    } else {
        const char *homePath = getenv("HOME");
        length = homePath ? snprintf(ame_sd_directory, sizeof(ame_sd_directory),
                                    "%s/Documents/shader-diagnostics", homePath) : -1;
    }
    if (length < 0 || (size_t)length >= sizeof(ame_sd_directory)) ame_sd_directory[0] = 0;
    if (ame_sd_directory[0] && mkdir(ame_sd_directory, 0700) != 0) {
        // An existing directory is fine; fopen reports other access failures.
    }
    fprintf(stderr, "[ShaderDiag] enabled; maxFailureGroups=%u maxModules=%u maxBytes=%u directory=%s\n",
            AME_SD_FAILURES, AME_SD_MODULES, AME_SD_BYTES,
            ame_sd_directory[0] ? ame_sd_directory : "unavailable");
}

static inline int ame_sd_enabled(void) {
    pthread_once(&ame_sd_once, ame_sd_init);
    return ame_sd_on;
}

static inline const char *ame_sd_format(VkFormat format) {
    switch (format) {
#define AME_SD_FORMAT(name) case VK_FORMAT_##name: return #name
        AME_SD_FORMAT(R8_UNORM); AME_SD_FORMAT(R8_SNORM);
        AME_SD_FORMAT(R8G8B8A8_UNORM); AME_SD_FORMAT(R8G8B8A8_UINT);
        AME_SD_FORMAT(R8G8B8A8_SINT); AME_SD_FORMAT(R8G8B8A8_SRGB);
        AME_SD_FORMAT(R16G16_SINT); AME_SD_FORMAT(R16G16_UINT);
        AME_SD_FORMAT(R16G16_SFLOAT); AME_SD_FORMAT(R16G16B16_UINT);
        AME_SD_FORMAT(R16G16B16_SINT); AME_SD_FORMAT(R16G16B16_USCALED);
        AME_SD_FORMAT(R16G16B16A16_SINT); AME_SD_FORMAT(R16G16B16A16_UINT);
        AME_SD_FORMAT(R32_SFLOAT); AME_SD_FORMAT(R32_UINT); AME_SD_FORMAT(R32_SINT);
        AME_SD_FORMAT(R32G32_UINT); AME_SD_FORMAT(R32G32_SINT); AME_SD_FORMAT(R32G32_SFLOAT);
        AME_SD_FORMAT(R32G32B32_SFLOAT); AME_SD_FORMAT(R32G32B32A32_SFLOAT);
#undef AME_SD_FORMAT
        default: return "other-see-VkFormat-number";
    }
}

static inline void ame_sd_shader(VkShaderModule module, const VkShaderModuleCreateInfo *info) {
    if (!ame_sd_enabled() || !info || !info->pCode) return;
    pthread_mutex_lock(&ame_sd_mutex);
    uint64_t serial = ++ame_sd_module_serial;
    unsigned slot = AME_SD_MODULES;
    for (unsigned i = 0; i < AME_SD_MODULES; ++i) {
        if (ame_sd_modules[i].handle == module) { slot = i; break; }
        if (!ame_sd_modules[i].handle && slot == AME_SD_MODULES) slot = i;
    }
    if (slot < AME_SD_MODULES) {
        ame_sd_modules[slot].handle = module;
        ame_sd_modules[slot].serial = serial;
    }
    // Capture each shader at most once per creation. Files have unique serials,
    // even when MoltenVK reuses handles across shaderpack reloads.
    if (serial <= AME_SD_MODULES && ame_sd_saved_modules < AME_SD_MODULES && info->codeSize <= AME_SD_BYTES - ame_sd_written_bytes &&
        ame_sd_directory[0]) {
        char path[1200];
        snprintf(path, sizeof(path), "%s/module-%llu.spv", ame_sd_directory, (unsigned long long)serial);
        FILE *file = fopen(path, "wb");
        if (file) {
            size_t written = fwrite(info->pCode, 1, info->codeSize, file);
            int close_result = fclose(file);
            ame_sd_written_bytes += written;
            ++ame_sd_saved_modules;
            fprintf(stderr, "[ShaderDiag] module=%llu handle=%p bytes=%zu saved=%d file=%s\n",
                    (unsigned long long)serial, (void *)(uintptr_t)module, info->codeSize,
                    written == info->codeSize && close_result == 0, path);
        } else {
            fprintf(stderr, "[ShaderDiag] module=%llu handle=%p dump-open-failed file=%s\n",
                    (unsigned long long)serial, (void *)(uintptr_t)module, path);
        }
    } else if (serial <= AME_SD_MODULES + 1) {
        fprintf(stderr, "[ShaderDiag] module=%llu handle=%p bytes=%zu dump-unavailable-or-budget-exhausted\n",
                (unsigned long long)serial, (void *)(uintptr_t)module, info->codeSize);
    }
    pthread_mutex_unlock(&ame_sd_mutex);
}

static inline uint64_t ame_sd_failure(uint32_t count, const VkGraphicsPipelineCreateInfo *infos, VkResult result) {
    if (!ame_sd_enabled()) return 0;
    pthread_mutex_lock(&ame_sd_mutex);
    uint64_t event = ++ame_sd_failure_serial;
    if (event > AME_SD_FAILURES) {
        if (event == AME_SD_FAILURES + 1) fprintf(stderr, "[ShaderDiag] failure snapshot budget exhausted\n");
        pthread_mutex_unlock(&ame_sd_mutex);
        return event;
    }
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    fprintf(stderr, "[ShaderDiag] failure=%llu utcEpoch=%lld.%03ld originalResult=%d pipelineCount=%u\n",
            (unsigned long long)event, (long long)now.tv_sec, now.tv_nsec / 1000000, result, count);
    for (uint32_t i = 0; infos && i < count && i < 8; ++i) {
        const VkGraphicsPipelineCreateInfo *info = infos + i;
        fprintf(stderr, "[ShaderDiag] failure=%llu index=%u flags=%u renderPass=%p subpass=%u pNext=%p stages=%u\n",
                (unsigned long long)event, i, info->flags, (void *)(uintptr_t)info->renderPass,
                info->subpass, info->pNext, info->stageCount);
        for (uint32_t j = 0; info->pStages && j < info->stageCount && j < 8; ++j) {
            const VkPipelineShaderStageCreateInfo *stage = info->pStages + j;
            uint64_t module = 0;
            for (unsigned k = 0; k < AME_SD_MODULES; ++k)
                if (ame_sd_modules[k].handle == stage->module) module = ame_sd_modules[k].serial;
            fprintf(stderr, "[ShaderDiag] failure=%llu index=%u stage=%u module=%llu handle=%p entry=%s pNext=%p specialization=%p\n",
                    (unsigned long long)event, i, stage->stage, (unsigned long long)module,
                    (void *)(uintptr_t)stage->module, stage->pName ? stage->pName : "null",
                    stage->pNext, (const void *)stage->pSpecializationInfo);
        }
        const VkPipelineVertexInputStateCreateInfo *input = info->pVertexInputState;
        if (input) {
            fprintf(stderr, "[ShaderDiag] failure=%llu index=%u vertexInputPNext=%p bindings=%u attributes=%u\n",
                    (unsigned long long)event, i, input->pNext,
                    input->vertexBindingDescriptionCount, input->vertexAttributeDescriptionCount);
            for (uint32_t j = 0; input->pVertexBindingDescriptions && j < input->vertexBindingDescriptionCount && j < 32; ++j) {
                const VkVertexInputBindingDescription *binding = input->pVertexBindingDescriptions + j;
                fprintf(stderr, "[ShaderDiag] failure=%llu index=%u binding=%u stride=%u rate=%u\n",
                        (unsigned long long)event, i, binding->binding, binding->stride, binding->inputRate);
            }
            for (uint32_t j = 0; input->pVertexAttributeDescriptions && j < input->vertexAttributeDescriptionCount && j < 32; ++j) {
                const VkVertexInputAttributeDescription *attribute = input->pVertexAttributeDescriptions + j;
                fprintf(stderr, "[ShaderDiag] failure=%llu index=%u attrIndex=%u location=%u binding=%u offset=%u format=%d:%s\n",
                        (unsigned long long)event, i, j, attribute->location, attribute->binding,
                        attribute->offset, attribute->format, ame_sd_format(attribute->format));
            }
        }
        if (info->pDynamicState) {
            for (uint32_t j = 0; info->pDynamicState->pDynamicStates && j < info->pDynamicState->dynamicStateCount && j < 32; ++j)
                fprintf(stderr, "[ShaderDiag] failure=%llu index=%u dynamicState=%d\n",
                        (unsigned long long)event, i, info->pDynamicState->pDynamicStates[j]);
        }
    }
    pthread_mutex_unlock(&ame_sd_mutex);
    return event;
}

// Fixed capacity; never evict a command and pretend its previous state is known.
static inline unsigned ame_sd_command_slot(VkCommandBuffer command) {
    unsigned empty = AME_SD_COMMANDS;
    for (unsigned i = 0; i < AME_SD_COMMANDS; ++i) {
        if (ame_sd_commands[i].command == command) return i;
        if (!ame_sd_commands[i].command && empty == AME_SD_COMMANDS) empty = i;
    }
    if (empty < AME_SD_COMMANDS) ame_sd_commands[empty].command = command;
    return empty;
}

static inline void ame_sd_begin(VkCommandBuffer command) {
    if (!ame_sd_enabled()) return;
    pthread_mutex_lock(&ame_sd_mutex);
    unsigned slot = ame_sd_command_slot(command);
    if (slot < AME_SD_COMMANDS) {
        ame_sd_commands[slot].pipeline = VK_NULL_HANDLE;
        ame_sd_commands[slot].began = 1;
    }
    pthread_mutex_unlock(&ame_sd_mutex);
}

static inline void ame_sd_bind(VkCommandBuffer command, VkPipeline pipeline) {
    if (!ame_sd_enabled()) return;
    pthread_mutex_lock(&ame_sd_mutex);
    unsigned slot = ame_sd_command_slot(command);
    if (slot < AME_SD_COMMANDS) ame_sd_commands[slot].pipeline = pipeline;
    pthread_mutex_unlock(&ame_sd_mutex);
}

static inline void ame_sd_skip(VkCommandBuffer command, VkPipeline suppressing_pipeline, const char *kind) {
    if (!ame_sd_enabled()) return;
    pthread_mutex_lock(&ame_sd_mutex);
    unsigned slot = ame_sd_command_slot(command);
    if (slot < AME_SD_COMMANDS) {
        uint64_t skips = ++ame_sd_commands[slot].skips;
        // At most 11 messages per command buffer, regardless of frame count.
        if (skips <= 1024 && (skips & (skips - 1)) == 0)
            fprintf(stderr, "[ShaderDiag] suppressed cmd=%p kind=%s count=%llu globalPipeline=%p commandPipeline=%p beginObserved=%d mismatch=%d\n",
                    (void *)command, kind, (unsigned long long)skips,
                    (void *)(uintptr_t)suppressing_pipeline, (void *)(uintptr_t)ame_sd_commands[slot].pipeline,
                    ame_sd_commands[slot].began, ame_sd_commands[slot].pipeline != suppressing_pipeline);
    }
    pthread_mutex_unlock(&ame_sd_mutex);
}
#endif
