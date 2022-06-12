//
//  main.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/2.
//

#import <UIKit/UIKit.h>
#import <SDL2/SDL_main.h>
#import "config.h"
#import "ViewController.h"

int main(int argc, char * argv[]) {
    NSLog(@"Hello scrcpy v%s", SCRCPY_VERSION);
    
    static UIWindow *window = nil;
    window = window ?: [[UIWindow alloc] init];
    
    UIStoryboard *sb = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    ViewController *mainController = [sb instantiateViewControllerWithIdentifier:@"ViewController"];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:mainController];
    [window makeKeyAndVisible];
    
    return 0;
}
