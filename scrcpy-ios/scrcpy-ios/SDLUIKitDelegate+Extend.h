//
//  SDLUIKitDelegate+Extend.h
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/11.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#define ScrcpyConnectWithSchemeNotification  @"ScrcpyConnectWithSchemeNotification"
#define ScrcpyConnectWithSchemeURLKey        @"URL"

#define ScrcpySwitchModeCommand        @"switch"
#define ScrcpySwitchModeKey            @"mode"
#define ScrcpyModeVNC                  @"vnc"
#define ScrcpyModeADB                  @"adb"

void ScrcpyReloadViewController(UIWindow *window);

@interface SDLUIKitDelegate : NSObject<UIApplicationDelegate>
@end

@interface SDLUIKitDelegate (Extend)
@end

NS_ASSUME_NONNULL_END
