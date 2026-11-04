#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
SHADER_TEST_DIR=$(mktemp -d /private/tmp/air-shader-tests.XXXXXX)
trap 'rm -rf "$SHADER_TEST_DIR"' EXIT
python3 - "$SHADER_TEST_DIR" <<'PY'
from pathlib import Path
import sys
source=Path('Natives/main_hook.m').read_text()
types=source[source.index('typedef int32_t VkZResult;'):source.index('// Stride fix 状态')]
helpers=source[source.index('// Debug-only extra hooks.'):source.index('// vkCmd* 真实函数指针')]
Path(sys.argv[1], 'diag-production.h').write_text('#include "ZinkShaderDiagnostics.h"\ntypedef int BOOL;\n'+types+helpers)
PY
clang -std=c11 -Wall -Wextra -Werror -pthread -I "$SHADER_TEST_DIR" -I Natives \
  -I "${VULKAN_HEADERS_DIR:-Natives/external/MobileGL/3rdparty/Vulkan-Headers/include}" \
  tests/shaders/DiagnosticsTests.c -o "$SHADER_TEST_DIR/tests"
AMETHYST_SHADER_DIAG=0 AMETHYST_SHADER_DIAG_DIR="$SHADER_TEST_DIR/off" "$SHADER_TEST_DIR/tests" disabled 2>"$SHADER_TEST_DIR/off.log"
AMETHYST_SHADER_DIAG=1 AMETHYST_SHADER_DIAG_DIR="$SHADER_TEST_DIR/on" "$SHADER_TEST_DIR/tests" enabled 2>"$SHADER_TEST_DIR/on.log"
python3 - "$SHADER_TEST_DIR" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]);off=(root/'off.log').read_text();on=(root/'on.log').read_text()
assert not off and not (root/'off').exists()
assert on.count('failure snapshot budget exhausted') == 1
assert on.count('originalResult=') == 32
assert on.count('[ShaderDiag] suppressed ') == 11
assert 'format=88:R16G16B16_UINT' in on and 'mismatch=1' in on
assert 'format=82:R16G16_SINT' in on and 'format=100:R32_SFLOAT' in on
files=list((root/'on').glob('*.spv')); assert len(files)==1 and files[0].stat().st_size==20
print('PASS: failure snapshots capped at 32; 4096 skipped draws produce 11 messages; SPIR-V byte budget enforced')
PY
# The artifact's explicit build flag must work without editing user preferences,
# and its runtime off switch must still take precedence.
clang -std=c11 -Wall -Wextra -Werror -pthread -DAMETHYST_SHADER_DIAG_BUILD=1 \
  -I "$SHADER_TEST_DIR" -I Natives \
  -I "${VULKAN_HEADERS_DIR:-Natives/external/MobileGL/3rdparty/Vulkan-Headers/include}" \
  tests/shaders/DiagnosticsTests.c -o "$SHADER_TEST_DIR/build-enabled-tests"
AMETHYST_SHADER_DIAG=0 AMETHYST_SHADER_DIAG_DIR="$SHADER_TEST_DIR/build-off" "$SHADER_TEST_DIR/build-enabled-tests" disabled 2>"$SHADER_TEST_DIR/build-off.log"
AMETHYST_SHADER_DIAG_DIR="$SHADER_TEST_DIR/build-on" env -u AMETHYST_SHADER_DIAG "$SHADER_TEST_DIR/build-enabled-tests" enabled 2>"$SHADER_TEST_DIR/build-on.log"
test ! -s "$SHADER_TEST_DIR/build-off.log"
test ! -e "$SHADER_TEST_DIR/build-off"
test -f "$SHADER_TEST_DIR/build-on/module-1.spv"
