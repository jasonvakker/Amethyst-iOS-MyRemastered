#!/bin/sh
# Pass the official LWJGL 3.3.3 natives-macos-arm64 JAR. This is a host test dependency,
# never an app/game dependency. Build JavaApp first with its normal Makefile.
set -eu
NATIVES_JAR=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$(dirname "$0")/../.."
GLFW_PROBE_DIR=$(mktemp -d /private/tmp/air-glfw-api-probe.XXXXXX)
trap 'rm -rf "$GLFW_PROBE_DIR"' EXIT
mkdir -p "$GLFW_PROBE_DIR/natives" "$GLFW_PROBE_DIR/classes"
unzip -q "$NATIVES_JAR" -d "$GLFW_PROBE_DIR/natives"
clang -dynamiclib -fobjc-arc -Wno-incomplete-implementation -framework Foundation -framework GameController -framework QuartzCore \
  tests/controller/NativeGamepadJNI.m -o "$GLFW_PROBE_DIR/AngelAuraAmethyst"
LWJGL_JAR=${LWJGL_JAR:-JavaApp/build/lwjgl-333.jar}
LAUNCHER_JAR=${LAUNCHER_JAR:-JavaApp/build/launcher.jar}
"${BOOTJDK:-/usr/bin}/javac" -cp "$LWJGL_JAR" -d "$GLFW_PROBE_DIR/classes" \
  tests/controller/NativeGamepadProbe.java tests/controller/GLFWApiProbe.java
BUNDLE_PATH="$GLFW_PROBE_DIR" "${BOOTJDK:-/usr/bin}/java" \
  -Dglfw.windowSize=1024x768 -DUIScreen.maximumFramesPerSecond=60 \
  "-Dorg.lwjgl.librarypath=$GLFW_PROBE_DIR/natives/macos/arm64/org/lwjgl" \
  -cp "$GLFW_PROBE_DIR/classes:$LWJGL_JAR:$LAUNCHER_JAR:JavaApp/libs/others/jsr305.jar" \
  org.lwjgl.glfw.GLFWApiProbe "$GLFW_PROBE_DIR/AngelAuraAmethyst"
