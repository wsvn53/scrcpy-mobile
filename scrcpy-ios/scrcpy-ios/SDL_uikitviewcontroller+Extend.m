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
#import "MenubarViewController.h"

@implementation SDL_uikitviewcontroller (Extend)

// Checked that SDL_uikitviewcontroller not implemented viewDidLoad
-(void)viewDidLoad {
    [super viewDidLoad];
    
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf addMenubarTriggerZone];
    });
}

-(void)addMenubarTriggerZone {
    CVCreate.UIView.addToView(self.view)
        .topAnchor(self.view.bottomAnchor, -40)
        .bottomAnchor(self.view.bottomAnchor, 0)
        .leftAnchor(self.view.leftAnchor, 0)
        .rightAnchor(self.view.rightAnchor, 0)
        .customView(^(UIView *view) {
            UILongPressGestureRecognizer *menuGesture = [[UILongPressGestureRecognizer alloc]
                                                         initWithTarget:self
                                                         action:@selector(onLongPress:)];
            menuGesture.minimumPressDuration = 1.f;
            [view addGestureRecognizer:menuGesture];
        });
}

-(void)onLongPress:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self showMenus];
    }
}

-(void)showMenus {
    MenubarViewController *menuController = [[MenubarViewController alloc] initWithNibName:nil bundle:nil];
    menuController.modalPresentationStyle = UIModalPresentationCustom;
    [self presentViewController:menuController animated:YES completion:nil];
    
//    [menuController addAction:[UIAlertAction actionWithTitle:@"Back Button" style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
//        [ScrcpySharedClient sendBackButton];
//    }]];
//    [menuController addAction:[UIAlertAction actionWithTitle:@"Home Button" style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
//        [ScrcpySharedClient sendHomeButton];
//    }]];
//    [menuController addAction:[UIAlertAction actionWithTitle:@"Switch App Button" style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
//        [ScrcpySharedClient sendSwitchAppButton];
//    }]];
//    [menuController addAction:[UIAlertAction actionWithTitle:@"Disconnect" style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
//        [ScrcpySharedClient stopScrcpy];
//    }]];
//    [menuController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:(UIAlertActionStyleCancel) handler:nil]];
//    [self presentViewController:menuController animated:YES completion:nil];
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
    for (CALayer *layer in self.view.layer.sublayers) {
        if ([layer isKindOfClass:AVSampleBufferDisplayLayer.class]) {
            layer.frame = self.view.bounds;
        }
    }
}

@end
