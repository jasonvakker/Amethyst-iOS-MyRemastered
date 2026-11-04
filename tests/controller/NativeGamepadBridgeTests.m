// Uses Apple's real synthetic extended-gamepad implementation. No physical device required.
#import "../../Natives/input/NativeGamepadBridge.m"
#include <assert.h>
#include <math.h>

static BOOL passthrough;
@implementation ControllerInput
+ (BOOL)isPassthrough { return passthrough; }
@end

int main(void) {
    @autoreleasepool {
        [NativeGamepadBridge reset];
        passthrough = YES;
        [NativeGamepadBridge refreshWithControllers:@[]];
        for (int i = 0; i < AM_GAMEPADS; i++) assert(!snapshots[i].present);
        GCController *controller = [GCController controllerWithExtendedGamepad];
        assert(controller.extendedGamepad);
        GCExtendedGamepad *g = controller.extendedGamepad;
        [g.leftThumbstick.xAxis setValue:0.375f];
        [g.leftThumbstick.yAxis setValue:0.625f];
        [g.rightThumbstick.xAxis setValue:-0.45f];
        [g.rightThumbstick.yAxis setValue:-0.8f];
        [g.leftTrigger setValue:0.25f];
        [g.rightTrigger setValue:0.75f];
        GCControllerButtonInput *buttons[] = {g.buttonA, g.buttonB, g.buttonX, g.buttonY,
            g.leftShoulder, g.rightShoulder, g.buttonOptions, g.buttonMenu, g.buttonHome,
            g.leftThumbstickButton, g.rightThumbstickButton,
            g.dpad.up, g.dpad.right, g.dpad.down, g.dpad.left};
        [NativeGamepadBridge refreshWithControllers:@[controller]];
        assert(snapshots[0].present && names[0].length && guids[0].length == 32);
        for (int i = 1; i < AM_GAMEPADS; i++) assert(!snapshots[i].present);
        assert(fabsf(snapshots[0].axes[0] - 0.375f) < 0.0001f);
        assert(fabsf(snapshots[0].axes[1] + 0.625f) < 0.0001f);
        assert(fabsf(snapshots[0].axes[2] + 0.45f) < 0.0001f);
        assert(fabsf(snapshots[0].axes[3] - 0.8f) < 0.0001f);
        assert(fabsf(snapshots[0].axes[4] + 0.5f) < 0.0001f);
        assert(fabsf(snapshots[0].axes[5] - 0.5f) < 0.0001f);
        uint32_t first = snapshots[0].generation;
        for (int b = 0; b < 11; b++) {
            if (!buttons[b]) continue; // Optional home/options may be absent on this model.
            [buttons[b] setValue:1];
            [NativeGamepadBridge refreshWithControllers:@[controller]];
            assert(snapshots[0].buttons[b] == 1);
            [buttons[b] setValue:0];
        }
        const float dpadX[] = {0, 1, 0, -1};
        const float dpadY[] = {1, 0, -1, 0};
        for (int d = 0; d < 4; d++) {
            [g.dpad.xAxis setValue:dpadX[d]];
            [g.dpad.yAxis setValue:dpadY[d]];
            [NativeGamepadBridge refreshWithControllers:@[controller]];
            assert(snapshots[0].buttons[11 + d] == 1);
            assert(snapshots[0].hat == (1 << d));
        }
        [g.dpad.yAxis setValue:1];
        [g.dpad.xAxis setValue:1];
        [NativeGamepadBridge refreshWithControllers:@[controller]];
        assert(snapshots[0].hat == 3);
        assert(snapshots[0].generation == first); // Input does not reconnect a device.
        passthrough = NO;
        [NativeGamepadBridge refreshWithControllers:@[controller]];
        assert(!snapshots[0].present && snapshots[0].generation != first);
        passthrough = YES;
        [NativeGamepadBridge refreshWithControllers:@[controller]];
        assert(snapshots[0].present);
        uint32_t second = snapshots[0].generation;
        [NativeGamepadBridge refreshWithControllers:@[]];
        assert(!snapshots[0].present && snapshots[0].generation != second);
        GCController *replacement = [GCController controllerWithExtendedGamepad];
        [NativeGamepadBridge refreshWithControllers:@[replacement]];
        assert(snapshots[0].present && snapshots[0].axes[4] == -1 && snapshots[0].axes[5] == -1);
        [NativeGamepadBridge reset];
        assert(!snapshots[0].present);
        puts("PASS: Apple synthetic gamepad analog axes, triggers, buttons, hats, hotplug, mode gating, reset");
    }
}
