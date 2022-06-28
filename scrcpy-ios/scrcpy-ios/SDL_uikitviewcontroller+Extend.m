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
    [self addMenubarTriggerZone];
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

-(void)addMenubarTriggerZone {
    if (self.viewLoaded == NO) {
        [self performSelector:@selector(addMenubarTriggerZone) withObject:nil afterDelay:0.5];
        return;
    }
    
    CVCreate.UIView.addToView(self.view)
        .topAnchor(self.view.bottomAnchor, -50)
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
