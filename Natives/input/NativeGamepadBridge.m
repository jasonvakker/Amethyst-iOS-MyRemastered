#import "NativeGamepadBridge.h"
#import "ControllerInput.h"
#import "../jni.h"
#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>
#include <stdint.h>
#include <string.h>

#define AM_GAMEPADS 16
// Wire format shared with GamepadBridge.java. No platform-sized fields.
typedef struct {
    uint32_t generation;
    uint32_t present;
    float axes[6];
    uint8_t buttons[15];
    uint8_t hat;
    uint8_t reserved[16];
} AMGamepadSnapshot;
_Static_assert(sizeof(AMGamepadSnapshot) == 64, "Gamepad snapshot ABI");

static AMGamepadSnapshot snapshots[AM_GAMEPADS];
static NSMutableArray *devices;
static NSString *names[AM_GAMEPADS], *guids[AM_GAMEPADS];

@implementation NativeGamepadBridge

+ (void)initialize {
    if (self != NativeGamepadBridge.class) return;
    devices = [NSMutableArray arrayWithCapacity:AM_GAMEPADS];
    for (int i = 0; i < AM_GAMEPADS; i++) [devices addObject:NSNull.null];
}

+ (void)reset {
    @synchronized(self) {
        for (int i = 0; i < AM_GAMEPADS; i++) {
            snapshots[i].generation++;
            snapshots[i].present = 0;
            memset(snapshots[i].axes, 0, sizeof(snapshots[i]) - 8);
            devices[i] = NSNull.null;
            names[i] = guids[i] = nil;
        }
    }
}

+ (void)refresh {
    NSAssert(NSThread.isMainThread, @"GameController sampling must run on main");
    [self refreshWithControllers:GCController.controllers];
}

+ (void)refreshWithControllers:(NSArray<GCController *> *)connected {
    @synchronized(self) {
        // Keep slots stable until disconnect, including while the mode is native.
        for (int i = 0; i < AM_GAMEPADS; i++) {
            if (devices[i] != NSNull.null && ![connected containsObject:devices[i]]) {
#ifndef NDEBUG
                NSLog(@"[ControllerBridge] GC disconnect jid=%d name=%@ guid=%@", i, names[i], guids[i]);
#endif
                devices[i] = NSNull.null;
                snapshots[i].generation++;
            }
        }
        for (GCController *controller in connected) {
            if (!controller.extendedGamepad || [devices containsObject:controller]) continue;
            NSUInteger slot = [devices indexOfObject:NSNull.null];
            if (slot == NSNotFound) break;
            devices[slot] = controller;
            snapshots[slot].generation++;
            BOOL dualSense = [controller.extendedGamepad isKindOfClass:NSClassFromString(@"GCDualSenseGamepad")];
            names[slot] = controller.vendorName ?: controller.productCategory ?: @"Apple GameController";
            if (dualSense) {
                names[slot] = @"Sony DualSense";
                // SDL-format GUID: USB-compatible Sony VID 054c / DualSense PID 0ce6.
                guids[slot] = @"030000004c050000e60c000000000000";
            } else {
                // Stable model identity, without inventing a USB vendor/product ID.
                uint64_t hash = 14695981039346656037ULL;
                for (const unsigned char *p = (const unsigned char *)names[slot].UTF8String; *p; p++)
                    hash = (hash ^ *p) * 1099511628211ULL;
                guids[slot] = [NSString stringWithFormat:@"0500000000000000%016llx", (unsigned long long)hash];
            }
#ifndef NDEBUG
            NSLog(@"[ControllerBridge] GC connect jid=%lu name=%@ category=%@ guid=%@ vid/pid=%@",
                  (unsigned long)slot, names[slot], controller.productCategory, guids[slot], dualSense ? @"054c/0ce6 (model)" : @"unavailable");
#endif
        }
        for (int i = 0; i < AM_GAMEPADS; i++) {
            AMGamepadSnapshot *s = &snapshots[i];
            BOOL present = [ControllerInput isPassthrough] && devices[i] != NSNull.null;
            if (s->present != present) s->generation++;
            s->present = present;
            memset(s->axes, 0, sizeof(*s) - 8);
            if (!present) continue;
            GCExtendedGamepad *g = [(GCController *)devices[i] extendedGamepad];
            s->axes[0] = g.leftThumbstick.xAxis.value;
            s->axes[1] = -g.leftThumbstick.yAxis.value; // GLFW Y increases down.
            s->axes[2] = g.rightThumbstick.xAxis.value;
            s->axes[3] = -g.rightThumbstick.yAxis.value;
            s->axes[4] = g.leftTrigger.value * 2.0f - 1.0f;
            s->axes[5] = g.rightTrigger.value * 2.0f - 1.0f;
            GCControllerButtonInput *buttons[] = {g.buttonA, g.buttonB, g.buttonX, g.buttonY,
                g.leftShoulder, g.rightShoulder, g.buttonOptions, g.buttonMenu, g.buttonHome,
                g.leftThumbstickButton, g.rightThumbstickButton,
                g.dpad.up, g.dpad.right, g.dpad.down, g.dpad.left};
            for (int b = 0; b < 15; b++) s->buttons[b] = buttons[b].isPressed ? 1 : 0;
            s->hat = (s->buttons[11] ? 1 : 0) | (s->buttons[12] ? 2 : 0)
                   | (s->buttons[13] ? 4 : 0) | (s->buttons[14] ? 8 : 0);
#ifndef NDEBUG
            static CFTimeInterval lastLog;
            if (CACurrentMediaTime() - lastLog > 2 &&
                (s->axes[0] || s->axes[1] || s->axes[2] || s->axes[3] ||
                 s->axes[4] > -1 || s->axes[5] > -1 || memchr(s->buttons, 1, 15))) {
                NSLog(@"[ControllerBridge] analog delivery jid=%d sticks=%.3f,%.3f/%.3f,%.3f triggers=%.3f,%.3f hat=%u",
                      i, s->axes[0], s->axes[1], s->axes[2], s->axes[3], s->axes[4], s->axes[5], s->hat);
                lastLog = CACurrentMediaTime();
            }
#endif
        }
    }
}
@end

JNIEXPORT void JNICALL Java_org_lwjgl_glfw_GamepadBridge_nativeSnapshot(
        JNIEnv *env, jclass clazz, jobject buffer, jobjectArray javaNames, jobjectArray javaGuids) {
    void *dest = (*env)->GetDirectBufferAddress(env, buffer);
    if (!dest || (*env)->GetDirectBufferCapacity(env, buffer) < sizeof(snapshots) ||
        (*env)->GetArrayLength(env, javaNames) < AM_GAMEPADS ||
        (*env)->GetArrayLength(env, javaGuids) < AM_GAMEPADS) return;
    @synchronized(NativeGamepadBridge.class) {
        for (int i = 0; i < AM_GAMEPADS; i++) {
            if (((AMGamepadSnapshot *)dest)[i].generation == snapshots[i].generation) continue;
            jstring name = snapshots[i].present ? (*env)->NewStringUTF(env, names[i].UTF8String) : NULL;
            jstring guid = snapshots[i].present ? (*env)->NewStringUTF(env, guids[i].UTF8String) : NULL;
            (*env)->SetObjectArrayElement(env, javaNames, i, name);
            (*env)->SetObjectArrayElement(env, javaGuids, i, guid);
            if (name) (*env)->DeleteLocalRef(env, name);
            if (guid) (*env)->DeleteLocalRef(env, guid);
        }
        memcpy(dest, snapshots, sizeof(snapshots));
    }
}
