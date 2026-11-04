#!/usr/bin/env python3
"""Run the *shipped* Controlify/JNA SDL loader with Air's GLFW override.
Usage: python3 tests/controller/verify_controlify.py controlify.jar jna-5.13.0.jar
Only Minecraft's logging/platform dependencies are stubbed; SDL loader, DebugProperties,
libsdl4j and JNA are the real classes. No game or configuration files are changed.
"""
import pathlib
import subprocess
import sys
import tempfile
import zipfile

mod, jna = map(lambda s: pathlib.Path(s).resolve(), sys.argv[1:3])
with tempfile.TemporaryDirectory(prefix="air-controlify-loader-") as tmp:
    root = pathlib.Path(tmp)
    with zipfile.ZipFile(mod) as z:
        debug = z.read("dev/isxander/controlify/debug/DebugProperties.class")
        if b"controlify.debug.sdl_natives_override" not in debug:
            sys.exit("UNSUPPORTED: this Controlify version has no SDL override; do not assume GLFW is selected")
        sdl = next(n for n in z.namelist() if n.startswith("META-INF/jarjar/libsdl4j-") and n.endswith(".jar"))
        (root / "libsdl4j.jar").write_bytes(z.read(sdl))
    files = {
        "dev/isxander/controlify/utils/log/ControlifyLogger.java": '''
package dev.isxander.controlify.utils.log;
public interface ControlifyLogger {
 default ControlifyLogger createSubLogger(String name) { return this; }
 default void log(String message) { System.out.println(message); }
 default void log(String message, Object... args) { System.out.println(message + java.util.Arrays.toString(args)); }
 default void error(String message, Throwable error, Object... args) { LogState.error = error; System.out.println(error); }
 default void error(String message, Throwable error) { LogState.error = error; System.out.println(error); }
 default void error(String message) { System.out.println(message); }
}''',
        "dev/isxander/controlify/utils/log/LogState.java": '''
package dev.isxander.controlify.utils.log;
public class LogState { public static Throwable error; }''',
        "dev/isxander/controlify/utils/CUtil.java": '''
package dev.isxander.controlify.utils;
import dev.isxander.controlify.utils.log.ControlifyLogger;
public class CUtil {
 public static final ControlifyLogger LOGGER = new ControlifyLogger() {};
 public static boolean IS_POJAV_LAUNCHER = false;
}''',
        "dev/isxander/controlify/platform/main/PlatformMainUtil.java": '''
package dev.isxander.controlify.platform.main;
public class PlatformMainUtil { public static boolean isDevEnv() { return false; } }''',
        "LoaderProbe.java": '''
import dev.isxander.controlify.driver.sdl.SDLNativesLoader;
import dev.isxander.controlify.utils.log.LogState;
public class LoaderProbe {
 public static void main(String[] args) {
  if (SDLNativesLoader.tryLoad() || SDLNativesLoader.isLoaded() || SDLNativesLoader.get().isPresent())
   throw new AssertionError("SDL initialized instead of selecting GLFW fallback");
  if (!(LogState.error instanceof UnsatisfiedLinkError) || !LogState.error.toString().contains("air-glfw-controller-backend"))
   throw new AssertionError("Loader failed for an unexpected reason", LogState.error);
  if (!SDLNativesLoader.hasAttemptedLoad() || SDLNativesLoader.tryLoad()) throw new AssertionError("Retry changed backend");
  System.out.println("PASS: real Controlify SDL loader returns false before SDL initialization; GLFW fallback selected");
 }
}'''
    }
    sources = []
    for name, content in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        sources.append(str(path))
    cp = f"{root}:{mod}:{root / 'libsdl4j.jar'}:{jna}"
    subprocess.run(["javac", "-cp", cp, "-d", str(root), *sources], check=True)
    subprocess.run(["java", "-Dcontrolify.debug.sdl_natives_override=/dev/null/air-glfw-controller-backend",
                    "-cp", cp, "LoaderProbe"], check=True)
    bytecode = subprocess.check_output(["javap", "-c", "-p", "-classpath", str(mod),
                                       "dev.isxander.controlify.Controlify"], text=True)
    assert "SDLNativesLoader.tryLoad" in bytecode and "GLFWControllerManager" in bytecode
    print("PASS: shipped Controlify initialization contains SDL loader and GLFW controller manager")
