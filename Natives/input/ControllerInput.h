#import <GameController/GameController.h>

@interface ControllerInput : NSObject

+ (BOOL)isPassthrough;
+ (void)setPassthrough:(BOOL)enabled;
+ (void)releaseAllInputs;
+ (void)shutdown;
+ (void)initKeycodeTable;
+ (void)registerControllerCallbacks:(GCController *)controller;
+ (void)unregisterControllerCallbacks:(GCController *)controller;
+ (void)tick;

@end
