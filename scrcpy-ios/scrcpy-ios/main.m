//
//  main.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/2.
//

#import <UIKit/UIKit.h>
#import <SDL2/SDL_main.h>
#import "KFKeychain.h"
#import "config.h"

#import "SDLUIKitDelegate+Extend.h"
#import "ViewController.h"
#import "VNCViewController.h"

int main(int argc, char * argv[]) {
    NSLog(@"Hello scrcpy v%s", SCRCPY_VERSION);
    
    static UIWindow *window = nil;
    window = window ?: [[UIWindow alloc] init];
    ScrcpyReloadViewController(window);
    [window makeKeyAndVisible];
    
    return 0;
}

void ScrcpyReloadViewController(UIWindow *window) {
    UIViewController *mainController = nil;
    NSString *mode = [KFKeychain loadObjectForKey:ScrcpySwitchModeKey];
    if ([mode isEqualToString:@"adb"]) {
        // mainController = [[ScrcpyViewController alloc] initWithNibName:nil bundle:nil];
        mainController = [[ViewController alloc] initWithNibName:nil bundle:nil];
    } else if (mode.length == 0 || [mode isEqualToString:@"vnc"]) {
        mainController = [[VNCViewController alloc] initWithNibName:nil bundle:nil];
    }
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:mainController];
}
