// Compile the production implementation with host adapters for UIKit/key injection.
#import "../../Natives/input/ControllerInput.h"
#import "../../Natives/input/NativeGamepadBridge.h"
#import "../../Natives/glfw_keycodes.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <assert.h>
#include <math.h>

#define ACTION_MOVE_MOTION 3
#define SPECIALBTN_MOUSEPRI -3
#define SPECIALBTN_MOUSESEC -4
#define SPECIALBTN_MOUSEMID -6
#define SPECIALBTN_SCROLLUP -7
#define SPECIALBTN_SCROLLDOWN -8
static BOOL isGrabbing = YES;
static NSMutableSet *keys, *mouseButtons;
static NSUInteger motions, keyEvents, bridgeRefreshes, bridgeResets;
static NSArray *testControllers;
void CallbackBridge_nativeSendKey(int key, int scan, int action, int mods) {
    keyEvents++;
    if (action) [keys addObject:@(key)]; else [keys removeObject:@(key)];
}
void CallbackBridge_nativeSendMouseButton(int button, int action, int mods) {
    if (action) [mouseButtons addObject:@(button)]; else [mouseButtons removeObject:@(button)];
}
void CallbackBridge_nativeSendScroll(CGFloat x, CGFloat y) {}
CGFloat MathUtils_dist(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) { return hypot(x2-x1, y2-y1); }
@interface PLProfiles : NSObject
+ (id)resolveKeyForCurrentProfile:(id)key;
@end
@implementation PLProfiles
+ (id)resolveKeyForCurrentProfile:(id)key { return @"default.json"; }
@end
NSMutableDictionary *parseJSONFromFile(NSString *path) {
    NSArray *map = @[
        @{@"gamepad_button": @(GLFW_GAMEPAD_BUTTON_A), @"keycode": @(GLFW_KEY_SPACE)},
        @{@"gamepad_button": @(GLFW_GAMEPAD_BUTTON_B), @"keycode": @(SPECIALBTN_MOUSEPRI)},
        @{@"gamepad_button": @(GLFW_GAMEPAD_BUTTON_X), @"keycode": @(-GLFW_KEY_LEFT_SHIFT)}];
    return @{@"mGameMappingList": map, @"mMenuMappingList": map}.mutableCopy;
}
@interface SurfaceViewController : NSObject
+ (instancetype)currentInstance;
- (void)sendTouchPoint:(CGPoint)point withEvent:(int)event;
@end
@implementation SurfaceViewController
+ (instancetype)currentInstance { static id instance; if (!instance) instance = [self new]; return instance; }
- (void)sendTouchPoint:(CGPoint)point withEvent:(int)event { motions++; }
@end
@implementation NativeGamepadBridge
+ (void)refresh { bridgeRefreshes++; }
+ (void)reset { bridgeResets++; }
@end
#include "ControllerInputProduction.m"

int main(void) {
    @autoreleasepool {
        keys = [NSMutableSet set]; mouseButtons = [NSMutableSet set];
        GCController *controller = [GCController controllerWithExtendedGamepad];
        testControllers = @[controller];
        Method controllersMethod = class_getClassMethod(GCController.class, @selector(controllers));
        IMP original = method_setImplementation(controllersMethod, imp_implementationWithBlock(^NSArray *(id cls) { return testControllers; }));
        setenv("POJAV_HOME", "/private/tmp", 1);
        assert(![ControllerInput isPassthrough]);
        [ControllerInput initKeycodeTable];
        [ControllerInput registerControllerCallbacks:controller];
        GCExtendedGamepad *g = controller.extendedGamepad;
        assert(g.buttonA.pressedChangedHandler && g.leftThumbstick.valueChangedHandler);
        void (^oldButton)(GCControllerButtonInput *, float, BOOL) = g.buttonA.pressedChangedHandler;
        void (^oldStick)(GCControllerDirectionPad *, float, float) = g.leftThumbstick.valueChangedHandler;
        oldButton(g.buttonA, 1, YES);
        g.buttonB.pressedChangedHandler(g.buttonB, 1, YES);
        g.buttonX.pressedChangedHandler(g.buttonX, 0, NO); // Sticky shift held.
        oldStick(g.leftThumbstick, 0.5, 0.5);
        g.rightThumbstick.valueChangedHandler(g.rightThumbstick, 0.5, 0.25);
        assert([keys containsObject:@(GLFW_KEY_SPACE)] && [keys containsObject:@(GLFW_KEY_LEFT_SHIFT)]);
        assert([keys containsObject:@(GLFW_KEY_W)] && [keys containsObject:@(GLFW_KEY_D)]);
        assert(mouseButtons.count == 1);
        [ControllerInput tick]; [ControllerInput tick];
        assert(motions > 0);
        [ControllerInput setPassthrough:YES];
        assert(keys.count == 0 && mouseButtons.count == 0 && !leftShiftHeld);
        assert(lastXValue == 0 && lastYValue == 0 && lastFrameTime == 0 && lastLThumbDirection == -2);
        assert(!g.buttonA.pressedChangedHandler && !g.leftThumbstick.valueChangedHandler && !g.rightThumbstick.valueChangedHandler);
        NSUInteger beforeKeys = keyEvents, beforeMotions = motions, beforeRefreshes = bridgeRefreshes;
        oldButton(g.buttonA, 1, YES); oldStick(g.leftThumbstick, 1, 1); // Late retained blocks must be inert.
        [ControllerInput registerControllerCallbacks:controller];
        [ControllerInput tick];
        assert(keyEvents == beforeKeys && motions == beforeMotions && bridgeRefreshes > beforeRefreshes);
        assert(!g.buttonA.pressedChangedHandler);
        [ControllerInput setPassthrough:NO];
        assert(g.buttonA.pressedChangedHandler && g.leftThumbstick.valueChangedHandler);
        g.buttonA.pressedChangedHandler(g.buttonA, 1, YES);
        assert([keys containsObject:@(GLFW_KEY_SPACE)]);
        [ControllerInput unregisterControllerCallbacks:controller]; [ControllerInput releaseAllInputs];
        assert(keys.count == 0 && !g.buttonA.pressedChangedHandler);
        [ControllerInput shutdown];
        assert(bridgeResets == 1 && !gameMap && !menuMap);
        method_setImplementation(controllersMethod, original);
        puts("PASS: production Air mode transitions release keys/mouse/sticky shift, detach callbacks, block late input, restore native controls");
    }
}
