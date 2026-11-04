#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
CONTROLLER_TEST_DIR=$(mktemp -d /private/tmp/air-controller-tests.XXXXXX)
trap 'rm -rf "$CONTROLLER_TEST_DIR"' EXIT
"${BOOTJDK:-/usr/bin}/javac" -source 8 -target 8 -d "$CONTROLLER_TEST_DIR" \
  JavaApp/src/lwjgl/org/lwjgl/glfw/GamepadBridge.java tests/controller/GamepadBridgeTests.java tests/controller/NativeGamepadProbe.java
"${BOOTJDK:-/usr/bin}/java" -cp "$CONTROLLER_TEST_DIR" org.lwjgl.glfw.GamepadBridgeTests
if [ "$(uname -s)" = Darwin ]; then
  python3 - "$CONTROLLER_TEST_DIR" <<'PYTEST'
from pathlib import Path
import sys
source = Path('Natives/ProfileSettingsViewController.m').read_text()
start = source.index('- (void)saveControllerMode {')
end = source.index('\n- (void)showControllerModeSelector', start)
(Path(sys.argv[1]) / 'ProfileControllerModeProduction.m').write_text(source[start:end])
PYTEST
  clang -fobjc-arc -framework Foundation -I "$CONTROLLER_TEST_DIR" \
    tests/controller/ProfileModeTests.m -o "$CONTROLLER_TEST_DIR/profile-mode-tests"
  "$CONTROLLER_TEST_DIR/profile-mode-tests"
  # Replace only UIKit imports, keeping the actual ControllerInput method bodies.
  sed '/^#import/d' Natives/input/ControllerInput.m > "$CONTROLLER_TEST_DIR/ControllerInputProduction.m"
  clang -fobjc-arc -framework Foundation -framework GameController -framework QuartzCore -framework CoreGraphics \
    -I "$CONTROLLER_TEST_DIR" -I Natives/input tests/controller/ControllerInputTests.m -o "$CONTROLLER_TEST_DIR/controller-input-tests"
  "$CONTROLLER_TEST_DIR/controller-input-tests"
  clang -fobjc-arc -Wno-incomplete-implementation -framework Foundation -framework GameController -framework QuartzCore \
    tests/controller/NativeGamepadBridgeTests.m -o "$CONTROLLER_TEST_DIR/native-gamepad-tests"
  "$CONTROLLER_TEST_DIR/native-gamepad-tests"
  clang -dynamiclib -fobjc-arc -Wno-incomplete-implementation -framework Foundation -framework GameController -framework QuartzCore \
    tests/controller/NativeGamepadJNI.m -o "$CONTROLLER_TEST_DIR/libcontroller-test.dylib"
  "${BOOTJDK:-/usr/bin}/java" -cp "$CONTROLLER_TEST_DIR" org.lwjgl.glfw.NativeGamepadProbe "$CONTROLLER_TEST_DIR/libcontroller-test.dylib"
fi
