#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
CONTROLLER_TEST_DIR=$(mktemp -d /private/tmp/air-controller-tests.XXXXXX)
trap 'rm -rf "$CONTROLLER_TEST_DIR"' EXIT
"${BOOTJDK:-/usr/bin}/javac" -source 8 -target 8 -d "$CONTROLLER_TEST_DIR" \
  JavaApp/src/lwjgl/org/lwjgl/glfw/GamepadBridge.java tests/controller/GamepadBridgeTests.java tests/controller/NativeGamepadProbe.java
"${BOOTJDK:-/usr/bin}/java" -cp "$CONTROLLER_TEST_DIR" org.lwjgl.glfw.GamepadBridgeTests
if [ "$(uname -s)" = Darwin ]; then
  clang -fobjc-arc -Wno-incomplete-implementation -framework Foundation -framework GameController -framework QuartzCore \
    tests/controller/NativeGamepadBridgeTests.m -o "$CONTROLLER_TEST_DIR/native-gamepad-tests"
  "$CONTROLLER_TEST_DIR/native-gamepad-tests"
  clang -dynamiclib -fobjc-arc -Wno-incomplete-implementation -framework Foundation -framework GameController -framework QuartzCore \
    tests/controller/NativeGamepadJNI.m -o "$CONTROLLER_TEST_DIR/libcontroller-test.dylib"
  "${BOOTJDK:-/usr/bin}/java" -cp "$CONTROLLER_TEST_DIR" org.lwjgl.glfw.NativeGamepadProbe "$CONTROLLER_TEST_DIR/libcontroller-test.dylib"
fi
