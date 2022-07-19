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

// ScrcpyMenubarGuideDidShow
static NSString *ScrcpyMenubarGuideDidShow = @"ScrcpyMenubarGuideDidShow";

@implementation SDL_uikitviewcontroller (Extend)

// Checked that SDL_uikitviewcontroller not implemented viewDidLoad
-(void)viewDidLoad {
    [super viewDidLoad];
    [self performSelector:@selector(addMenubarTriggerView) withObject:nil afterDelay:1.f];
}

-(void)showMenubarGuide {
    BOOL guideDidShow = [[NSUserDefaults standardUserDefaults] boolForKey:ScrcpyMenubarGuideDidShow];
    if (guideDidShow) {
        NSLog(@"Menubar Guide Did Show");
        return;
    }
    
    CVCreate.UIStackView(@[
            CVCreate.UIView,
            CVCreate.UIStackView(@[
                CVCreate.UIImageView([UIImage imageNamed:@"TouchIcon"])
                    .size(CGSizeMake(30, 30))
                    .customView(^(UIImageView *view){
                        view.contentMode = UIViewContentModeCenter;
                    }),
                CVCreate.UILabel.text(@"Long Press To Show Menu Bar")
                    .boldFontSize(15.f)
                    .textAlignment(NSTextAlignmentCenter)
                    .textColor(UIColor.whiteColor),
            ]).spacing(10),
            CVCreate.UIView,
        ])
        .distribution(UIStackViewDistributionEqualSpacing)
        .addToView(self.view)
        .click(self, @selector(hideGuideView))
        .border(UIColor.whiteColor, 1.f)
        .backgroundColor([UIColor colorWithWhite:1 alpha:0.3])
        .topAnchor(self.view.bottomAnchor, -60)
        .bottomAnchor(self.view.bottomAnchor, 0)
        .leftAnchor(self.view.leftAnchor, 0)
        .rightAnchor(self.view.rightAnchor, 0)
        .customView(^(UIView *view){
            view.tag = @"GuideView".hash;
        });
}

-(void)hideGuideView {
    UIView *guideView = [self.view viewWithTag:@"GuideView".hash];
    [UIView animateWithDuration:0.3 animations:^{
        guideView.alpha = 0;
    } completion:^(BOOL finished) {
        // Mark as shown
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:ScrcpyMenubarGuideDidShow];
        
        // Remove GuideView and Show Menubar
        [guideView removeFromSuperview];
        [self showMenubarView];
    }];
}

-(void)addMenubarTriggerView {
    if (self.viewLoaded == NO) {
        [self performSelector:@selector(addMenubarTriggerView) withObject:nil afterDelay:0.5];
        return;
    }
    
    CVCreate.UIView.addToView(self.view)
        .topAnchor(self.view.bottomAnchor, -60)
        .bottomAnchor(self.view.bottomAnchor, 0)
        .leftAnchor(self.view.leftAnchor, 0)
        .rightAnchor(self.view.rightAnchor, 0)
        .customView(^(UIView *view) {
            UILongPressGestureRecognizer *menuGesture = [[UILongPressGestureRecognizer alloc]
                                                         initWithTarget:self
                                                         action:@selector(onLongPress:)];
            menuGesture.minimumPressDuration = 0.5f;
            [view addGestureRecognizer:menuGesture];
        });
    
    [self showMenubarGuide];
}

-(void)onLongPress:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self showMenubarView];
        [self hideGuideView];
    }
}

-(void)showMenubarView {
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
