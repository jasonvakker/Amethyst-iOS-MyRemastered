package org.lwjgl.glfw;
import java.nio.*;
import java.util.*;

public class GamepadBridgeTests {
    static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
    public static void main(String[] args) {
        ByteBuffer wire = ByteBuffer.allocate(16 * 64).order(ByteOrder.nativeOrder());
        GamepadBridge bridge = new GamepadBridge((out, names, guids) -> {
            for (int i = 0; i < wire.capacity(); i++) out.put(i, wire.get(i));
            names[0] = "Sony DualSense";
            guids[0] = "030000004c050000e60c000000000000";
        });
        List<String> events = new ArrayList<>();
        bridge.setListener((jid, connected) -> events.add(jid + ":" + connected));
        bridge.poll();
        for (int i = -1; i <= 16; i++) check(!bridge.present(i), "phantom " + i);
        check(bridge.axes(0) == null && bridge.buttons(0) == null && bridge.name(0) == null, "absent values");
        wire.putInt(0, 1).putInt(4, 1);
        float[] axes = {0.375f, -0.625f, -0.45f, 0.8f, -0.5f, 0.5f};
        for (int a = 0; a < 6; a++) wire.putFloat(8 + a * 4, axes[a]);
        for (int b = 0; b < 15; b++) wire.put(32 + b, (byte)(b % 2));
        wire.put(47, (byte)3);
        bridge.refresh(); // Querying state must not consume connection notifications.
        check(events.isEmpty(), "callback outside event pump");
        bridge.poll(); bridge.poll();
        check(events.equals(Arrays.asList("0:true")), "duplicate connect " + events);
        check(bridge.present(0) && !bridge.present(1), "one device");
        check(bridge.name(0).equals("Sony DualSense") && bridge.guid(0).length() == 32, "identity");
        FloatBuffer firstAxes = bridge.axes(0);
        check(firstAxes.isDirect() && firstAxes.remaining() == 6, "axes ABI");
        for (int a = 0; a < 6; a++) check(firstAxes.get(a) == axes[a], "analog precision " + a);
        firstAxes.position(4);
        check(bridge.axes(0).position() == 0, "buffer cursor leaks");
        for (int b = 0; b < 15; b++) check(bridge.buttons(0).get(b) == b % 2, "button layout " + b);
        check(bridge.hats(0).get(0) == 3, "hat diagonal");
        bridge.userPointer(0, 42); check(bridge.userPointer(0) == 42, "pointer");
        wire.putInt(0, 2).putInt(4, 0); bridge.poll();
        check(events.equals(Arrays.asList("0:true", "0:false")), "disconnect");
        check(bridge.axes(0) == null && bridge.hats(0) == null && bridge.userPointer(0) == 0, "stale disconnected state");
        wire.putInt(0, 3).putInt(4, 1); bridge.poll();
        wire.putInt(0, 5); bridge.poll(); // Unplug/replug between frames, reusing the same jid.
        check(events.subList(2, events.size()).equals(Arrays.asList("0:true", "0:false", "0:true")), "slot reuse " + events);
        bridge.setListener(null); wire.putInt(0, 6).putInt(4, 0); bridge.poll();
        check(events.size() == 5, "callback cleanup");
        bridge.reset();
        System.out.println("PASS: GLFW snapshot lifecycle, hotplug callbacks, analog buffers, layout, pointer cleanup");
    }
}
