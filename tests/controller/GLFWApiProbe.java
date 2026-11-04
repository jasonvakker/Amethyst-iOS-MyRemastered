package org.lwjgl.glfw;
import java.lang.reflect.Method;
import java.nio.*;

/** Optional host check of the actual assembled GLFW API, using a macOS LWJGL native. */
public class GLFWApiProbe {
    private static void scenario(int value) throws Exception {
        Method scenario = NativeGamepadProbe.class.getDeclaredMethod("scenario", int.class);
        scenario.setAccessible(true);
        scenario.invoke(null, value);
    }
    public static void main(String[] args) throws Exception {
        System.load(args[0]);
        scenario(0);
        for (int i = -1; i <= 16; i++) {
            if (GLFW.glfwJoystickPresent(i) || GLFW.glfwJoystickIsGamepad(i) ||
                GLFW.glfwGetJoystickName(i) != null || GLFW.glfwGetGamepadName(i) != null ||
                GLFW.glfwGetJoystickGUID(i) != null || GLFW.glfwGetJoystickAxes(i) != null ||
                GLFW.glfwGetJoystickButtons(i) != null || GLFW.glfwGetJoystickHats(i) != null)
                throw new AssertionError("phantom through GLFW API " + i);
        }
        try (GLFWGamepadState state = GLFWGamepadState.calloc()) {
            if (GLFW.glfwGetGamepadState(0, state)) throw new AssertionError("absent gamepad state");
            scenario(1);
            if (!GLFW.glfwJoystickPresent(0) || !GLFW.glfwJoystickIsGamepad(0) ||
                !GLFW.glfwGetGamepadState(0, state) || GLFW.glfwGetGamepadName(0) == null ||
                GLFW.glfwGetJoystickGUID(0).length() != 32 || state.axes(0) != 0.375f ||
                state.axes(4) != -1f || state.axes(5) != 0.5f || state.buttons(0) != 1)
                throw new AssertionError("GLFWGamepadState mapping");
            FloatBuffer axes = GLFW.glfwGetJoystickAxes(0);
            ByteBuffer buttons = GLFW.glfwGetJoystickButtons(0);
            if (!axes.isDirect() || axes.remaining() != 6 || !buttons.isDirect() || buttons.remaining() != 15 ||
                axes.get(0) != state.axes(0) || buttons.get(0) != state.buttons(0))
                throw new AssertionError("raw joystick buffers");
            scenario(2);
            if (GLFW.glfwJoystickPresent(0) || GLFW.glfwGetGamepadState(0, state))
                throw new AssertionError("native-mode leak through GLFW API");
        }
        System.out.println("PASS: assembled GLFW APIs enumerate real synthetic device and return native analog gamepad state");
    }
}
