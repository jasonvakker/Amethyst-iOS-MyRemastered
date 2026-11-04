#!/bin/bash
set -euo pipefail
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
PATCH_BUILD_DIR=$(mktemp -d "${RUNNER_TEMP:-/private/tmp}/amethyst-mvk129.XXXXXX")
MOLTENVK_SOURCE="$PATCH_BUILD_DIR/MoltenVK"
SPIRV_SOURCE="$PATCH_BUILD_DIR/SPIRV-Cross"
mkdir -p "$MOLTENVK_SOURCE" "$SPIRV_SOURCE"
curl -L --fail --silent --show-error https://codeload.github.com/KhronosGroup/MoltenVK/tar.gz/refs/tags/v1.2.9 -o "$PATCH_BUILD_DIR/moltenvk.tar.gz"
curl -L --fail --silent --show-error https://codeload.github.com/KhronosGroup/SPIRV-Cross/tar.gz/84cdc3b68e5ef5a15ecfacda77c61f24a9080cf9 -o "$PATCH_BUILD_DIR/spirv-cross.tar.gz"
printf '%s  %s\n' f415a09385030c6510a936155ce211f617c31506db5fbc563e804345f1ecf56e "$PATCH_BUILD_DIR/moltenvk.tar.gz" | shasum -a 256 -c -
printf '%s  %s\n' ab6a6c980048b72b44c341ffea63d1e91c3e5387a8c30cb03016dac9bc02ece6 "$PATCH_BUILD_DIR/spirv-cross.tar.gz" | shasum -a 256 -c -
tar -xzf "$PATCH_BUILD_DIR/moltenvk.tar.gz" -C "$MOLTENVK_SOURCE" --strip-components=1
tar -xzf "$PATCH_BUILD_DIR/spirv-cross.tar.gz" -C "$SPIRV_SOURCE" --strip-components=1
test "$(cat "$MOLTENVK_SOURCE/ExternalRevisions/SPIRV-Cross_repo_revision")" = 84cdc3b68e5ef5a15ecfacda77c61f24a9080cf9

compile_regression() {
    clang++ -std=c++14 -O0 -I "$SPIRV_SOURCE" "$PROJECT_ROOT/tests/shaders/PackedInputTests.cpp" \
      "$SPIRV_SOURCE/spirv_cross.cpp" "$SPIRV_SOURCE/spirv_parser.cpp" \
      "$SPIRV_SOURCE/spirv_cross_parsed_ir.cpp" "$SPIRV_SOURCE/spirv_cfg.cpp" \
      "$SPIRV_SOURCE/spirv_glsl.cpp" "$SPIRV_SOURCE/spirv_msl.cpp" -o "$PATCH_BUILD_DIR/packed-input-test"
}
compile_regression
"$PATCH_BUILD_DIR/packed-input-test" original
patch --fuzz=0 -d "$SPIRV_SOURCE" -p1 < "$PROJECT_ROOT/patches/spirv-cross-packed-vertex-input.patch"
compile_regression
"$PATCH_BUILD_DIR/packed-input-test" fixed
if [[ "${1:-}" == --verify-only ]]; then
    echo "Verified pinned source/backport; no iOS build attempted. Sources: $PATCH_BUILD_DIR"
    exit 0
fi
cd "$MOLTENVK_SOURCE"
./fetchDependencies --ios --spirv-cross-root "$SPIRV_SOURCE"
xcodebuild build -quiet -project MoltenVKPackaging.xcodeproj \
  -scheme 'MoltenVK Package (iOS only)' -destination 'generic/platform=iOS' \
  -configuration Release CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=14.0
PATCHED_LIBRARY="$MOLTENVK_SOURCE/Package/Release/MoltenVK/dynamic/MoltenVK.xcframework/ios-arm64/MoltenVK.framework/MoltenVK"
test -f "$PATCHED_LIBRARY"
DESTINATION="$PROJECT_ROOT/Natives/resources/Frameworks/libMoltenVK.dylib"
cp "$PATCHED_LIBRARY" "$DESTINATION"
install_name_tool -id @rpath/libMoltenVK.dylib "$DESTINATION"
# App packaging applies its own signature after the install-name change.
otool -L "$DESTINATION"
nm -gU "$DESTINATION" | grep ' _vkCreateGraphicsPipelines$'
mkdir -p "$PROJECT_ROOT/artifacts"
{
    echo 'MoltenVK v1.2.9; SPIRV-Cross 84cdc3b68e5ef5a15ecfacda77c61f24a9080cf9'
    echo 'Backport: host-format correction for Component-packed vertex stage inputs'
    shasum -a 256 "$DESTINATION" "$PROJECT_ROOT/patches/spirv-cross-packed-vertex-input.patch"
} > "$PROJECT_ROOT/artifacts/moltenvk-packed-input-build.txt"
