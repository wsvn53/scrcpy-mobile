//
//  SDL_uikitviewcontroller+Extend.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/11.
//

#import "SDL_uikitviewcontroller+Extend.h"
#import <AVFoundation/AVFoundation.h>
#import "CVCreate.h"
#import "ScrcpyClient.h"

@implementation SDL_uikitviewcontroller (Extend)

// Checked that SDL_uikitviewcontroller not implemented viewDidLoad
-(void)viewDidLoad {
    [super viewDidLoad];
    
    // Add Navigation Menu here
    UILongPressGestureRecognizer *menuGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPress:)];
    menuGesture.minimumPressDuration = 1.f;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf.view addGestureRecognizer:menuGesture];
    });
}

-(void)onLongPress:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    
    CGPoint touchPoint = [gesture locationOfTouch:0 inView:self.view];
    if (touchPoint.x < 10 || self.view.bounds.size.width - touchPoint.x < 10) {
        // Only support touched inner 10pt
        [self showMenus];
    }
}

-(void)showMenus {
    UIAlertController *menuController = [UIAlertController alertControllerWithTitle:nil message:@"Scrcpy Remote" preferredStyle:(UIAlertControllerStyleActionSheet)];
    [menuController addAction:[UIAlertAction actionWithTitle:@"Back Button" style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        [ScrcpySharedClient sendBackButton];
    }]];
    [menuController addAction:[UIAlertAction actionWithTitle:@"Home Button" style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        [ScrcpySharedClient sendHomeButton];
    }]];
    [menuController addAction:[UIAlertAction actionWithTitle:@"Menu Button" style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        [ScrcpySharedClient sendMenuButton];
    }]];
    [menuController addAction:[UIAlertAction actionWithTitle:@"Disconnect" style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        [ScrcpySharedClient stopScrcpy];
    }]];
    [menuController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:(UIAlertActionStyleCancel) handler:nil]];
    [self presentViewController:menuController animated:YES completion:nil];
}

-(void)dismissMenu:(UITapGestureRecognizer *)gesture {
    [UIView animateWithDuration:0.3 animations:^{
        gesture.view.alpha = 0;
    } completion:^(BOOL finished) {
        [gesture.view removeFromSuperview];
    }];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self.view.layer.sublayers enumerateObjectsUsingBlock:^(CALayer *layer, NSUInteger idx, BOOL *stop) {
        layer.frame = self.view.bounds;
    }];
}

@end
