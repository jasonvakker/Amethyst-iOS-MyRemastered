package org.lwjgl.glfw;
import java.util.*;
public class NativeGamepadProbe {
    private static native void scenario(int scenario);
    public static void main(String[] args) {
        System.load(args[0]);
        scenario(0);
        GamepadBridge bridge = new GamepadBridge();
        List<Boolean> events = new ArrayList<>();
        bridge.setListener((jid, connected) -> events.add(connected));
        bridge.poll();
        if (bridge.present(0)) throw new AssertionError("native phantom");
        scenario(1); bridge.poll();
        if (!bridge.present(0) || bridge.name(0) == null || bridge.guid(0).length() != 32 ||
            bridge.axis(0, 0) != 0.375f || bridge.axis(0, 4) != -1f ||
            bridge.axis(0, 5) != 0.5f || bridge.button(0, 0) != 1)
            throw new AssertionError("GameController/JNI wire state");
        scenario(2); bridge.poll(); // Native mode removes the mod-visible device.
        if (bridge.present(0)) throw new AssertionError("native mode leaked gamepad to mod");
        scenario(1); bridge.poll();
        scenario(0); bridge.poll();
        if (!events.equals(Arrays.asList(true, false, true, false))) throw new AssertionError(events);
        System.out.println("PASS: real Apple GameController -> production JNI -> Java analog state and lifecycle");
    }
}
