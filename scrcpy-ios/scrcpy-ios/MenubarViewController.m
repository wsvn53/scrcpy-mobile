//
//  MenubarViewController.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/28.
//

#import "MenubarViewController.h"
#import "CVCreate.h"
#import "ScrcpyClient.h"

@interface MenubarViewController ()

@end

@implementation MenubarViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
}

-(void)setupViews {
    self.view.backgroundColor = [UIColor clearColor];
    
    CVCreate.withView(self.view).click(self, @selector(dismiss:));
    
    CVCreate.UIStackView(@[
        CVCreate.UIView,
        CVCreate.UIStackView(@[
            CVCreate.UIView.size(CGSizeMake(70, 10)),
            CVCreate.UIImageView([UIImage imageNamed:@"BackIcon"])
                .customView(^(UIImageView *view){
                    view.contentMode = UIViewContentModeCenter;
                }),
            CVCreate.UILabel.text(@"Back").fontSize(13)
                .textColor(UIColor.whiteColor)
                .textAlignment(NSTextAlignmentCenter),
            CVCreate.UIView,
        ]).axis(UILayoutConstraintAxisVertical)
            .click(self, @selector(sendBackButton:)),
        CVCreate.UIView,
        CVCreate.UIStackView(@[
            CVCreate.UIView.size(CGSizeMake(70, 10)),
            CVCreate.UIImageView([UIImage imageNamed:@"HomeIcon"])
                .customView(^(UIImageView *view){
                    view.contentMode = UIViewContentModeCenter;
                }),
            CVCreate.UILabel.text(@"Home").fontSize(13)
                .textColor(UIColor.whiteColor)
                .textAlignment(NSTextAlignmentCenter),
            CVCreate.UIView,
        ]).axis(UILayoutConstraintAxisVertical)
            .click(self, @selector(sendHomeButton:)),
        CVCreate.UIView,
        CVCreate.UIStackView(@[
            CVCreate.UIView.size(CGSizeMake(70, 10)),
            CVCreate.UIImageView([UIImage imageNamed:@"SwitchAppIcon"])
                .customView(^(UIImageView *view){
                    view.contentMode = UIViewContentModeCenter;
                }),
            CVCreate.UILabel.text(@"Switch").fontSize(13)
                .textColor(UIColor.whiteColor)
                .textAlignment(NSTextAlignmentCenter),
            CVCreate.UIView,
        ]).axis(UILayoutConstraintAxisVertical)
            .click(self, @selector(sendSwitchAppButton:)),
        CVCreate.UIView,
        CVCreate.UIStackView(@[
            CVCreate.UIView.size(CGSizeMake(70, 10)),
            CVCreate.UIImageView([UIImage imageNamed:@"DisconnectIcon"])
                .customView(^(UIImageView *view){
                    view.contentMode = UIViewContentModeCenter;
                }),
            CVCreate.UILabel.text(@"Stop").fontSize(13)
                .textColor(UIColor.whiteColor)
                .textAlignment(NSTextAlignmentCenter),
            CVCreate.UIView,
        ]).axis(UILayoutConstraintAxisVertical)
            .click(self, @selector(sendDisconnectButton:)),
        CVCreate.UIView,
    ]).axis(UILayoutConstraintAxisHorizontal)
    .distribution(UIStackViewDistributionEqualCentering)
    .backgroundColor([UIColor colorWithWhite:0 alpha:0.8])
    .size(CGSizeMake(0, 80))
    .addToView(self.view)
    .click(self, @selector(doNothing))
    .centerXAnchor(self.view.centerXAnchor, 0)
    .widthAnchor(self.view.widthAnchor, 0)
    .bottomAnchor(self.view.bottomAnchor, 0);
}

-(void)doNothing {}

-(void)dismiss:(UITapGestureRecognizer *)gesture {
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void)clickAnimated:(UITapGestureRecognizer *)tap {
    [UIView animateWithDuration:0.3 delay:0 options:0 animations:^{
        tap.view.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
    } completion:^(BOOL finished) {
        tap.view.backgroundColor = UIColor.clearColor;
    }];
}

-(void)sendBackButton:(UITapGestureRecognizer *)tap {
    [self clickAnimated:tap];
    [ScrcpySharedClient sendBackButton];
}

-(void)sendHomeButton:(UITapGestureRecognizer *)tap {
    [self clickAnimated:tap];
    [ScrcpySharedClient sendHomeButton];
}

-(void)sendSwitchAppButton:(UITapGestureRecognizer *)tap {
    [self clickAnimated:tap];
    [ScrcpySharedClient sendSwitchAppButton];
}

-(void)sendDisconnectButton:(UITapGestureRecognizer *)tap {
    [self clickAnimated:tap];
    [ScrcpySharedClient stopScrcpy];
}

@end
