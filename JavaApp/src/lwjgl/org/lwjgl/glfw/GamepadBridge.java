package org.lwjgl.glfw;

import java.nio.*;
import java.util.Arrays;

/** GameController snapshots; connection callbacks are dispatched only by GLFW's event pump. */
final class GamepadBridge {
    static final int COUNT = 16, STRIDE = 64;
    interface Source { void snapshot(ByteBuffer states, String[] names, String[] guids); }
    interface Listener { void connection(int jid, boolean connected); }
    private static native void nativeSnapshot(ByteBuffer states, String[] names, String[] guids);
    private final Source source;
    private final ByteBuffer states = ByteBuffer.allocateDirect(COUNT * STRIDE).order(ByteOrder.nativeOrder());
    private final String[] names = new String[COUNT], guids = new String[COUNT];
    private final int[] notifiedGeneration = new int[COUNT];
    private final boolean[] notifiedPresent = new boolean[COUNT];
    private final long[] userPointers = new long[COUNT];
    private Listener listener;

    private static final boolean DEBUG = Boolean.getBoolean("air.controller.debug");
    private static boolean nativeLogged;
    private static void readNativeSnapshot(ByteBuffer states, String[] names, String[] guids) {
        nativeSnapshot(states, names, guids);
        if (DEBUG && !nativeLogged) {
            nativeLogged = true;
            System.out.println("[ControllerBridge] JNI snapshot bridge resolved from Air executable; no SDL controller library loaded");
        }
    }
    GamepadBridge() { this(GamepadBridge::readNativeSnapshot); }
    GamepadBridge(Source source) { this.source = source; }
    private static boolean valid(int jid) { return jid >= 0 && jid < COUNT; }
    synchronized void refresh() { source.snapshot(states, names, guids); }
    synchronized void setListener(Listener listener) {
        refresh();
        this.listener = listener;
        for (int i = 0; i < COUNT; i++) {
            notifiedGeneration[i] = states.getInt(i * STRIDE);
            notifiedPresent[i] = present(i);
        }
    }
    synchronized void poll() {
        refresh();
        for (int i = 0; i < COUNT; i++) {
            int generation = states.getInt(i * STRIDE);
            boolean present = present(i);
            if (generation == notifiedGeneration[i]) continue;
            boolean wasPresent = notifiedPresent[i];
            notifiedGeneration[i] = generation;
            notifiedPresent[i] = present;
            userPointers[i] = 0;
            // A different device can replace the old one in the same slot between polls.
            if (listener != null && wasPresent) listener.connection(i, false);
            if (listener != null && present) listener.connection(i, true);
            if (DEBUG) System.out.println("[ControllerBridge] GLFW delivery jid=" + i + " present=" + present
                + " name=" + names[i] + " guid=" + guids[i] + " generation=" + generation);
        }
    }
    synchronized boolean present(int jid) { return valid(jid) && states.getInt(jid * STRIDE + 4) != 0; }
    synchronized String name(int jid) { return present(jid) ? names[jid] : null; }
    synchronized String guid(int jid) { return present(jid) ? guids[jid] : null; }
    synchronized FloatBuffer axes(int jid) {
        if (!present(jid)) return null;
        ByteBuffer copy = ByteBuffer.allocateDirect(24).order(ByteOrder.nativeOrder());
        for (int a = 0; a < 6; a++) copy.putFloat(axis(jid, a));
        copy.flip();
        return copy.asFloatBuffer();
    }
    synchronized ByteBuffer buttons(int jid) {
        if (!present(jid)) return null;
        ByteBuffer copy = ByteBuffer.allocateDirect(15);
        for (int b = 0; b < 15; b++) copy.put(button(jid, b));
        return (ByteBuffer)copy.flip();
    }
    synchronized ByteBuffer hats(int jid) {
        if (!present(jid)) return null;
        return (ByteBuffer)ByteBuffer.allocateDirect(1).put(states.get(jid * STRIDE + 47)).flip();
    }
    synchronized float axis(int jid, int axis) { return states.getFloat(jid * STRIDE + 8 + axis * 4); }
    synchronized byte button(int jid, int button) { return states.get(jid * STRIDE + 32 + button); }
    synchronized long userPointer(int jid) { return present(jid) ? userPointers[jid] : 0; }
    synchronized void userPointer(int jid, long pointer) { if (present(jid)) userPointers[jid] = pointer; }
    synchronized void reset() {
        listener = null;
        Arrays.fill(notifiedGeneration, 0);
        Arrays.fill(notifiedPresent, false);
        Arrays.fill(userPointers, 0);
    }
}
