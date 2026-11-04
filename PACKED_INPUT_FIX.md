# Packed vertex input backport

The b6076b0 iPad capture supplies 116 SPIR-V modules and 21 failed pipeline
snapshots. All 11 Complementary failures use modules 19/65: signed scalar inputs
at Component 2, or Components 0 and 2, backed by R16G16B16_UINT entity records.
MakeUp's module 87 has the same issue at Component 1. Suppressed indexed draws
were observed, with the tracked per-command-buffer pipeline matching the dummy
used by the launcher's suppression check in every emitted sample.

MoltenVK 1.2.9 passes UINT16 format hints to SPIRV-Cross. Plain inputs receive
`ensure_correct_input_type`; reconstructed `m_location_N` vectors in the packed
input path do not. Adding more per-component hints alone did not fix the capture.
The backport applies the existing correction to the reconstructed vertex-input
vector, without changing buffer bytes, VkFormats, strides, fragment varyings,
renderer settings or the shaderpack's logical integer calculations.

The iPad modules were converted locally with MoltenVK 1.2.9's exact SPIRV-Cross
revision. Original MSL reproduced the UShort3/signed-input rejection on an Apple
M4 Pro host. With this backport, modules 19, 65 and 87 created Metal pipelines.
Those host tests used depth-only pipelines and aligned synthetic vertex bindings;
they did not draw a Minecraft frame, validate the original 54-byte stride, or run
on the iPad. MakeUp's Float-to-int modules 105/107/111 remained rejected as an
intentional negative control, demonstrating a separate incompatibility.

`scripts/build-moltenvk-packed-inputs.sh` verifies pinned source archive hashes,
reproduces the defect with a self-authored minimal shader, applies the four-line
backport, and runs the regression again. CI builds an iOS arm64 library from
MoltenVK **1.2.9**, not a wholesale stack upgrade, and packages it in this isolated
branch. The upstream build configuration is recorded; equivalence to all options
of the original prebuilt dylib is not established and remains a validation risk.

The default renderer and controller implementation remain unchanged. The old
format/stride retry code is left untouched in this first measured fix so only
the packed-input correction changes rendering behavior. Its known bad retries
must not be mistaken for successful rendering or retained as a final solution
for unresolved errors.

MakeUp 9.6 separately declares `attribute int blockEntityId` in its shared vertex
source, unlike a uniform provided by Iris. Captured Sodium terrain has a scalar
signed integer input supplied by a stride-zero R32_SFLOAT attribute. A visibly
named pack copy changing that declaration to `uniform int blockEntityId` is a
separate source-level candidate; no installed pack or Iris JAR is silently replaced.

Full iPad rendering, depth, shadows, transparency, shader-OFF behavior and
performance acceptance are still pending.
