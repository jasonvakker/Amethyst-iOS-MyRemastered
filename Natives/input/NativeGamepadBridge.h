#import <Foundation/Foundation.h>

// Main-thread producer; JNI only copies the cached state and never waits on UIKit.
@interface NativeGamepadBridge : NSObject
+ (void)refresh;
+ (void)reset;
@end
