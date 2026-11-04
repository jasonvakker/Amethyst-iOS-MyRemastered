#import "ControllerInput.h"
#import "NativeGamepadBridge.h"
#include <stdatomic.h>
#import "../LauncherPreferences.h"
#import "../PLProfiles.h"
#import "../SurfaceViewController.h"
#import "../utils.h"

#include "../glfw_keycodes.h"

// Left thumbstick directions
#define DIRECTION_EAST 0
#define DIRECTION_NORTH_EAST 1
//#define DIRECTION_NORTH 2
#define DIRECTION_NORTH_WEST 3
//#define DIRECTION_WEST 4
#define DIRECTION_SOUTH_WEST 5
//#define DIRECTION_SOUTH 6
#define DIRECTION_SOUTH_EAST 7
#define MOUSE_MAX_ACCELERATION 2

CFAbsoluteTime lastFrameTime;
CGFloat lastXValue; // lastHorizontalValue
CGFloat lastYValue; // lastVerticalValue

@implementation ControllerInput

NSMutableDictionary *gameMap, *menuMap;
BOOL leftShiftHeld;
static atomic_bool controllerPassthrough;
static NSMutableSet<NSNumber *> *heldKeys, *heldMouseButtons;
static NSHashTable<GCController *> *registeredControllers;
static char lastLThumbDirection = -2;

+ (BOOL)isPassthrough { return atomic_load(&controllerPassthrough); }

+ (void)emitKey:(int)key pressed:(BOOL)pressed {
    if (!heldKeys) heldKeys = [NSMutableSet set];
    if (pressed) [heldKeys addObject:@(key)]; else [heldKeys removeObject:@(key)];
    CallbackBridge_nativeSendKey(key, 0, pressed, 0);
}

+ (void)emitMouse:(int)button pressed:(BOOL)pressed {
    if (!heldMouseButtons) heldMouseButtons = [NSMutableSet set];
    if (pressed) [heldMouseButtons addObject:@(button)]; else [heldMouseButtons removeObject:@(button)];
    CallbackBridge_nativeSendMouseButton(button, pressed, 0);
}

+ (void)releaseAllInputs {
    for (NSNumber *key in heldKeys) CallbackBridge_nativeSendKey(key.intValue, 0, 0, 0);
    for (NSNumber *button in heldMouseButtons) CallbackBridge_nativeSendMouseButton(button.intValue, 0, 0);
    [heldKeys removeAllObjects];
    [heldMouseButtons removeAllObjects];
    lastXValue = lastYValue = lastFrameTime = 0;
    lastLThumbDirection = -2;
    leftShiftHeld = NO;
}

+ (void)setPassthrough:(BOOL)enabled {
    NSAssert(NSThread.isMainThread, @"Controller mode changes must run on main");
    if ([self isPassthrough] == enabled) return;
    // Remove our old blocks before changing ownership; no stale key/button can survive.
    for (GCController *controller in GCController.controllers) [self unregisterControllerCallbacks:controller];
    [self releaseAllInputs];
    atomic_store(&controllerPassthrough, enabled);
    if (!enabled) {
        [self initKeycodeTable];
        for (GCController *controller in GCController.controllers) [self registerControllerCallbacks:controller];
    }
    [NativeGamepadBridge refresh];
#ifndef NDEBUG
    NSLog(@"[ControllerBridge] mode=%@ backend=GLFW/GameController", enabled ? @"Controller Mod Passthrough (Controlify)" : @"Air Native Controls");
#endif
}

+ (void)shutdown {
    for (GCController *controller in GCController.controllers) [self unregisterControllerCallbacks:controller];
    [self releaseAllInputs];
    [NativeGamepadBridge reset];
    gameMap = menuMap = nil;
}

+ (void)initKeycodeTable {
    if (gameMap && menuMap) {
        return;
    }
    
    NSString *controlFile = [PLProfiles resolveKeyForCurrentProfile:@"defaultGamepadCtrl"];
    NSString *gamepadPath = [NSString stringWithFormat:@"%s/controlmap/gamepads/%@", getenv("POJAV_HOME"), controlFile];
    NSMutableDictionary *gamepadJSON = parseJSONFromFile(gamepadPath);
    
    gameMap = gamepadJSON[@"mGameMappingList"];
    menuMap = gamepadJSON[@"mMenuMappingList"];
}

+ (void)sendKeyEvent:(int)controllerKeycode pressed:(BOOL)pressed {
    if ([self isPassthrough]) return;
    int keycode = GLFW_KEY_UNKNOWN;
    __block NSMutableDictionary *mapping;
    if (isGrabbing) {
        mapping = gameMap;
    } else {
        mapping = menuMap;
    }
    
    for (NSMutableDictionary *buttonDict in mapping) {
        if(controllerKeycode == [buttonDict[@"gamepad_button"] intValue]) {
            keycode = [buttonDict[@"keycode"] intValue];
        }
    }

    switch (keycode) {
        case GLFW_KEY_UNKNOWN:
            // Do nothing
            break;
        case -GLFW_KEY_LEFT_SHIFT:
            if (!pressed) {
                leftShiftHeld = !leftShiftHeld;
                [self emitKey:GLFW_KEY_LEFT_SHIFT pressed:leftShiftHeld];
            }
            break;
        case SPECIALBTN_MOUSEPRI:
            [self emitMouse:GLFW_MOUSE_BUTTON_LEFT pressed:pressed];
            break;
        case SPECIALBTN_MOUSEMID:
            [self emitMouse:GLFW_MOUSE_BUTTON_MIDDLE pressed:pressed];
            break;
        case SPECIALBTN_MOUSESEC:
            [self emitMouse:GLFW_MOUSE_BUTTON_RIGHT pressed:pressed];
            break;
        case SPECIALBTN_SCROLLUP:
            CallbackBridge_nativeSendScroll(0, pressed ? 1 : 0);
            break;
        case SPECIALBTN_SCROLLDOWN:
            CallbackBridge_nativeSendScroll(0, pressed ? -1 : 0);
            break;
        default:
            if (keycode == GLFW_KEY_LEFT_SHIFT) {
                leftShiftHeld = pressed;
            }
            [self emitKey:keycode pressed:pressed];
            break;
    }
}

+ (void)registerControllerCallbacks:(GCController *)controller {
    if ([self isPassthrough]) return;
    if (!registeredControllers) registeredControllers = [NSHashTable weakObjectsHashTable];
    [registeredControllers addObject:controller];
    controller.handlerQueue = dispatch_get_main_queue();
    GCExtendedGamepad *gamepad = controller.extendedGamepad;

    gamepad.leftShoulder.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_LEFT_BUMPER pressed:pressed];
    };
    gamepad.rightShoulder.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER pressed:pressed];
    };

    gamepad.leftTrigger.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_LEFT_TRIGGER pressed:pressed];
    };
    gamepad.rightTrigger.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_RIGHT_TRIGGER pressed:pressed];
    };
    gamepad.buttonOptions.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_BACK pressed:pressed];
    };
    gamepad.buttonMenu.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_START pressed:pressed];
    };
    gamepad.buttonHome.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_GUIDE pressed:pressed];
    };

    gamepad.buttonA.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_A pressed:pressed];
    };
    gamepad.buttonB.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_B pressed:pressed];
    };
    gamepad.buttonX.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_X pressed:pressed];
    };
    gamepad.buttonY.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_Y pressed:pressed];
    };

    gamepad.dpad.up.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_DPAD_UP pressed:pressed];
    };
    gamepad.dpad.down.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_DPAD_DOWN pressed:pressed];
    };
    gamepad.dpad.left.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_DPAD_LEFT pressed:pressed];
    };
    gamepad.dpad.right.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_DPAD_RIGHT pressed:pressed];
    };

    gamepad.leftThumbstick.valueChangedHandler = ^(GCControllerDirectionPad * _Nonnull dpad, float xValue, float yValue) {
        if ([self isPassthrough]) return;
        if (!isGrabbing) {
            // Update virtual mouse position
            lastXValue = xValue;
            lastYValue = yValue;
            return;
        }

        char direction = -1;
        // 同 ControlJoystick：测"偏离中心"用或而非与。手柄更常见——GCController
        // 在死区内把轴直接 snap 到 0，前推带轻微侧漂也会被误判为静止。
        if (xValue != 0 || yValue != 0) {
            CGFloat degree = atan2f(yValue, xValue) * (180.0 / M_PI);
            if (degree < 0) {
                degree += 360;
            }
            direction = (int)((degree+22.5)/45.0) % 8;
        }
        if (lastLThumbDirection == direction) {
            return;
        }

        // Update WASD states
        [self emitKey:GLFW_KEY_W pressed:
            direction >= DIRECTION_NORTH_EAST &&
            direction <= DIRECTION_NORTH_WEST];
        [self emitKey:GLFW_KEY_A pressed:
            direction >= DIRECTION_NORTH_WEST &&
            direction <= DIRECTION_SOUTH_WEST];
        [self emitKey:GLFW_KEY_S pressed:
            direction >= DIRECTION_SOUTH_WEST &&
            direction <= DIRECTION_SOUTH_EAST];
        [self emitKey:GLFW_KEY_D pressed:
            direction == DIRECTION_SOUTH_EAST ||
            direction == DIRECTION_EAST ||
            direction == DIRECTION_NORTH_EAST];

        lastLThumbDirection = direction;
    };
    gamepad.rightThumbstick.valueChangedHandler = ^(GCControllerDirectionPad * _Nonnull dpad, float xValue, float yValue) {
        if ([self isPassthrough]) return;
        if (isGrabbing) {
            lastXValue = xValue;
            lastYValue = yValue;
        }
    };
    gamepad.leftThumbstickButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_LEFT_THUMB pressed:pressed];
    };
    gamepad.rightThumbstickButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        [self sendKeyEvent:GLFW_GAMEPAD_BUTTON_RIGHT_THUMB pressed:pressed];
    };
}

/**
 * Send the new mouse position, computing the delta
 */
+ (void)tick {
    [NativeGamepadBridge refresh];
    if ([self isPassthrough]) return;
    // There isn't a convenient way to get ns, use ms at this point
    CGFloat frameTime = CACurrentMediaTime();
    // GameController automatically performs deadzone calculations
    // so we just take the raw input
    if (lastFrameTime != 0 && (lastXValue != 0 || lastYValue != 0)) {
        CGFloat acceleration = pow(MathUtils_dist(0, 0, lastXValue, lastYValue), MOUSE_MAX_ACCELERATION); // magnitude
        if (acceleration > 1) acceleration = 1;

        // Compute delta since last tick time
        CGFloat deltaX = lastXValue * acceleration * 18;
        CGFloat deltaY = -lastYValue * acceleration * 18;
        CGFloat deltaTimeScale = (frameTime - lastFrameTime) / (1.0/60.0); // Scale of 1 = 60Hz
        deltaX *= deltaTimeScale;
        deltaY *= deltaTimeScale;

        SurfaceViewController *vc = [SurfaceViewController currentInstance];
        if (vc) {
            [vc sendTouchPoint:CGPointMake(deltaX, deltaY) withEvent:ACTION_MOVE_MOTION];
        }
    }
    lastFrameTime = frameTime;
}

+ (void)unregisterControllerCallbacks:(GCController *)controller {
    if (![registeredControllers containsObject:controller]) return;
    [registeredControllers removeObject:controller];
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    gamepad.leftShoulder.pressedChangedHandler = nil;
    gamepad.rightShoulder.pressedChangedHandler = nil;
    gamepad.leftTrigger.pressedChangedHandler = nil;
    gamepad.rightTrigger.pressedChangedHandler = nil;
    gamepad.buttonOptions.pressedChangedHandler = nil;
    gamepad.buttonMenu.pressedChangedHandler = nil;
    gamepad.buttonHome.pressedChangedHandler = nil;
    gamepad.buttonA.pressedChangedHandler = nil;
    gamepad.buttonB.pressedChangedHandler = nil;
    gamepad.buttonX.pressedChangedHandler = nil;
    gamepad.buttonY.pressedChangedHandler = nil;
    gamepad.dpad.up.pressedChangedHandler = nil;
    gamepad.dpad.down.pressedChangedHandler = nil;
    gamepad.dpad.left.pressedChangedHandler = nil;
    gamepad.dpad.right.pressedChangedHandler = nil;
    gamepad.leftThumbstick.valueChangedHandler = nil;
    gamepad.rightThumbstick.valueChangedHandler = nil;
    gamepad.leftThumbstickButton.pressedChangedHandler = nil;
    gamepad.rightThumbstickButton.pressedChangedHandler = nil;
}

@end
