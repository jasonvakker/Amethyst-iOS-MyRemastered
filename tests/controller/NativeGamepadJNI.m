// Host-only JNI fixture: production snapshot code, Apple's synthetic controller, no UIKit.
#import "../../Natives/input/NativeGamepadBridge.m"
static BOOL passthrough;
@implementation ControllerInput
+ (BOOL)isPassthrough { return passthrough; }
@end
JNIEXPORT void JNICALL Java_org_lwjgl_glfw_NativeGamepadProbe_scenario(JNIEnv *env, jclass cls, jint scenario) {
    @autoreleasepool {
        static GCController *controller;
        if (!controller) controller = [GCController controllerWithExtendedGamepad];
        passthrough = scenario != 2;
        [controller.extendedGamepad.leftThumbstick.xAxis setValue:0.375f];
        [controller.extendedGamepad.rightTrigger setValue:0.75f];
        [controller.extendedGamepad.buttonA setValue:1];
        [NativeGamepadBridge refreshWithControllers:scenario == 0 ? @[] : @[controller]];
    }
}
