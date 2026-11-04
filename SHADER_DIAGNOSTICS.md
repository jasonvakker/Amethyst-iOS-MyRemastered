# Iris / Zink diagnostic build

This branch adds observations to the existing Zink hooks. It is not a rendering fix.
It starts at the validated Controlify branch, preserving controller code, renderer
defaults, NeoForge/LWJGL compatibility, shaderpacks and profile persistence.

The dedicated IPA workflow opts in with `AMETHYST_SHADER_DIAG_BUILD=1`. Ordinary
builds remain disabled. Runtime `AMETHYST_SHADER_DIAG=0` disables observations even
in that diagnostic artifact; `AMETHYST_SHADER_DIAG=1` enables them in a normal
build. No environment setting is written into launcher preferences.

When enabled:

- The original failed `vkCreateGraphicsPipelines` call is logged before the old
  retries mutate any descriptions: exact Vulkan format names/numbers, locations,
  offsets, binding strides, shader modules, render pass, dynamic state and pointers
  indicating extension/specialization state. Non-null `pNext` or specialization
  pointers indicate additional state that this snapshot does not decode.
- `vkCreateShaderModule` forwards its arguments/result and saves the supplied
  SPIR-V after success. Module serials link files to the pipeline snapshot and stay
  unique across reused Vulkan handles and shaderpack reloads. A missing serial or
  dump must be treated as missing evidence, not as an empty shader.
- Suppressed draws are counted using the existing suppression decision. Independent
  command-buffer tracking reports whether the global pipeline used for that
  decision differs from the last observed graphics bind in that command buffer.
  `vkBeginCommandBuffer` resets that diagnostic binding state after success. The
  existing global binding implementation and its draw behavior are not changed.

Output is bounded per process: 32 failed pipeline groups, 512 shader files and
16 MiB of SPIR-V; 64 tracked command buffers; at most 11 suppressed-draw messages
per tracked command buffer. Counts are process lifetime counts, not frame counts
or definitive counts per entity program. Shader writes occur only at compilation,
with no GPU readbacks or per-frame state queries. Diagnostics add CPU/I/O overhead;
use a build with them disabled for performance acceptance.

Files go to `Documents/shader-diagnostics` in the application container. A writable
`AMETHYST_SHADER_DIAG_DIR` can override the destination. The current launcher log
includes `[ShaderDiag]` events. No MoltenVK shader-dump environment setting is
assumed to exist, and no validation layer is assumed installed.

## One device capture

After the IPA has built and is ready, use a disposable world / duplicate Oritech
profile, keeping the current renderer and mods. Enable Complementary, wait for
the reported missing entities, then select MakeUp and wait for its missing terrain.
Exit the game. Preserve the **current** native launcher log, Java `latest.log`, and
the `shader-diagnostics` folder before another launch rotates the log. No further
diagnostic shaderpacks or quality-option sweep is required for this capture.

This capture distinguishes the original UShort3/signed-input disagreement from
the MakeUp Float/integer-input failure and from the launcher's known bad retries
(82→83 is short2→half2; 100→101 is float→uint2). It cannot by itself prove correct
framebuffer contents, native Vulkan validity or a complete fix.

## Validation

`tests/shaders/run.sh` compiles the real diagnostic helpers and wrapper bodies
against the vendored Khronos types. It checks disabled behavior, unchanged Vulkan
arguments/results and vertex data, ABI layout, command-buffer attribution, concurrent
failure snapshots and file/log budgets. The IPA workflow also runs the existing
controller bridge tests and builds the full app. Host tests are not an iPad GPU test.
