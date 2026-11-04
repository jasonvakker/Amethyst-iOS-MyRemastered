#import <Foundation/Foundation.h>
#include <assert.h>
@interface PLProfiles : NSObject
@property NSMutableDictionary *profiles;
@property NSUInteger saves;
+ (instancetype)current;
- (void)saveProfile:(NSMutableDictionary *)profile withName:(NSString *)name;
@end
@implementation PLProfiles
+ (instancetype)current { static id current; if (!current) current = [self new]; return current; }
- (void)saveProfile:(NSMutableDictionary *)profile withName:(NSString *)name { self.profiles[name] = profile; self.saves++; }
@end
@interface ProfileSettingsViewController : NSObject
@property NSMutableDictionary *profile;
@property NSString *selectedControllerMode;
@property NSString *originalName;
- (void)saveControllerMode;
@end
@implementation ProfileSettingsViewController
#include "ProfileControllerModeProduction.m"
@end
int main(void) {
    @autoreleasepool {
        NSDictionary *initial = @{@"name": @"Oritech", @"lastVersionId": @"1.21.1-neoforge-21.1.238",
            @"allocatedMemory": @8192, @"javaVersion": @{@"majorVersion": @21, @"component": @"java-runtime-delta"},
            @"javaArgs": @"-Dkeep=original", @"gameDir": @"modpacks/oritech", @"customSetting": @[@1, @2]};
        PLProfiles.current.profiles = [@{@"Oritech": initial.mutableCopy} mutableCopy];
        ProfileSettingsViewController *editor = [ProfileSettingsViewController new];
        editor.originalName = @"Oritech"; editor.profile = initial.mutableCopy;
        editor.profile[@"name"] = @"Unconfirmed rename";
        for (NSString *mode in @[@"controlify", @"native"]) {
            editor.selectedControllerMode = mode;
            [editor saveControllerMode];
            NSMutableDictionary *saved = [PLProfiles.current.profiles[@"Oritech"] mutableCopy];
            assert([saved[@"controllerMode"] isEqual:mode]);
            assert([editor.profile[@"controllerMode"] isEqual:mode]);
            [saved removeObjectForKey:@"controllerMode"];
            assert([saved isEqual:initial]); // Includes missing inherited renderer/API keys.
            assert([editor.profile[@"name"] isEqual:@"Unconfirmed rename"]);
        }
        assert(PLProfiles.current.saves == 2);
        editor.originalName = @"New unsaved profile";
        [editor saveControllerMode];
        assert(PLProfiles.current.saves == 2 && PLProfiles.current.profiles.count == 1);
        puts("PASS: production profile mode save preserves memory, renderer inheritance, JVM args, version, game directory and unrelated fields");
    }
}
