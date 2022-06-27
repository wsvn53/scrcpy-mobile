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
            CVCreate.UIView.size(CGSizeMake(0, 10)),
            CVCreate.UIImageView([UIImage imageNamed:@"BackIcon"])
                .customView(^(UIImageView *view){
                    view.contentMode = UIViewContentModeCenter;
                }),
            CVCreate.UILabel.text(@"Back").fontSize(15)
                .textColor(UIColor.whiteColor)
                .textAlignment(NSTextAlignmentCenter),
            CVCreate.UIView,
        ]).axis(UILayoutConstraintAxisVertical)
            .click(ScrcpySharedClient, @selector(sendBackButton)),
        CVCreate.UIView,
        CVCreate.UIStackView(@[
            CVCreate.UIView.size(CGSizeMake(0, 10)),
            CVCreate.UIImageView([UIImage imageNamed:@"HomeIcon"])
                .customView(^(UIImageView *view){
                    view.contentMode = UIViewContentModeCenter;
                }),
            CVCreate.UILabel.text(@"Home").fontSize(15)
                .textColor(UIColor.whiteColor)
                .textAlignment(NSTextAlignmentCenter),
            CVCreate.UIView,
        ]).axis(UILayoutConstraintAxisVertical)
            .click(ScrcpySharedClient, @selector(sendHomeButton)),
        CVCreate.UIView,
        CVCreate.UIStackView(@[
            CVCreate.UIView.size(CGSizeMake(0, 10)),
            CVCreate.UIImageView([UIImage imageNamed:@"SwitchAppIcon"])
                .customView(^(UIImageView *view){
                    view.contentMode = UIViewContentModeCenter;
                }),
            CVCreate.UILabel.text(@"Switch").fontSize(14)
                .textColor(UIColor.whiteColor)
                .textAlignment(NSTextAlignmentCenter),
            CVCreate.UIView,
        ]).axis(UILayoutConstraintAxisVertical)
            .click(ScrcpySharedClient, @selector(sendSwitchAppButton)),
        CVCreate.UIView,
        CVCreate.UIStackView(@[
            CVCreate.UIView.size(CGSizeMake(0, 10)),
            CVCreate.UIImageView([UIImage imageNamed:@"DisconnectIcon"])
                .customView(^(UIImageView *view){
                    view.contentMode = UIViewContentModeCenter;
                }),
            CVCreate.UILabel.text(@"Stop").fontSize(15)
                .textColor(UIColor.whiteColor)
                .textAlignment(NSTextAlignmentCenter),
            CVCreate.UIView,
        ]).axis(UILayoutConstraintAxisVertical)
            .click(ScrcpySharedClient, @selector(stopScrcpy)),
        CVCreate.UIView,
    ]).axis(UILayoutConstraintAxisHorizontal)
    .distribution(UIStackViewDistributionFillEqually)
    .backgroundColor([UIColor colorWithWhite:0 alpha:0.9])
    .size(CGSizeMake(0, 80))
    .addToView(self.view)
    .centerXAnchor(self.view.centerXAnchor, 0)
    .widthAnchor(self.view.widthAnchor, 0)
    .bottomAnchor(self.view.bottomAnchor, 0);
}

-(void)dismiss:(UITapGestureRecognizer *)gesture {
    if (gesture.view != self.view) { return; }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
