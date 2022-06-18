//
//  SDLUIKitDelegate+Extend.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/11.
//

#import "SDLUIKitDelegate+Extend.h"
#import "KFKeychain.h"

@implementation SDLUIKitDelegate (Extend)

-(void)applicationDidEnterBackground:(UIApplication *)application {
    // For more time execute in background
    static void (^beginTaskHandler)(void) = nil;
    beginTaskHandler = ^{
        [UIApplication.sharedApplication beginBackgroundTaskWithName:@"scrcpy" expirationHandler:beginTaskHandler];
    };
    beginTaskHandler();
}

-(BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options
{
    NSLog(@"> Received URL: %@", url.absoluteURL);
    
    // Handle Mode Switch URL
    if ([@[ScrcpySwitchModeCommand, ScrcpyModeADB, ScrcpyModeVNC] containsObject:url.host]) {
        [self switchScrcpyMode:url];
        return YES;
    }
    
    // Post connect
    [NSNotificationCenter.defaultCenter postNotificationName:ScrcpyConnectWithSchemeNotification object:nil userInfo:@{
        ScrcpyConnectWithSchemeURLKey : url
    }];
    return YES;
}

-(void)switchScrcpyMode:(NSURL *)switchURL {
    // URL likes scrcpy2://switch?mode=adb|vnc
    NSURLComponents *comps = [NSURLComponents componentsWithURL:switchURL resolvingAgainstBaseURL:NO];
    NSArray *modeItems = [comps.queryItems filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF.name == %@", ScrcpySwitchModeKey]];
    if (modeItems.lastObject != nil) {
        NSURLQueryItem *modeItem = (NSURLQueryItem *)modeItems.lastObject;
        [self saveScecpyMode:modeItem.value];
        return;
    }
    
    // URL likes scrcpy2://adb|vnc
    [self saveScecpyMode:switchURL.host];
}

-(void)saveScecpyMode:(NSString *)mode {
    [KFKeychain saveObject:mode forKey:ScrcpySwitchModeKey];
    NSLog(@"-> Scrcpy switched to %@ mode", mode);
    
    NSString *message = [NSString stringWithFormat:@"Scrcpy is switched to %@ mode. Please restart app again.", mode];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Scrcpy"
                                                                   message:message
                                                            preferredStyle:(UIAlertControllerStyleAlert)];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:(UIAlertActionStyleDefault) handler:nil]];
    
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow) [window.rootViewController presentViewController:alert animated:YES completion:nil];
    }
}

@end
