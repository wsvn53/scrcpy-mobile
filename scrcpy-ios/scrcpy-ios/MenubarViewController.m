//
//  MenubarViewController.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/28.
//

#import "MenubarViewController.h"
#import "CVCreate.h"
#import "ScrcpyClient.h"

@interface MenubarBackgroundView : UIView
// Proxy touches to target SDL view
@property (nonatomic, weak)  UIView *targetSDLView;

@end

@implementation MenubarBackgroundView

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        if (touch.view != self) return;
    }
    [self.targetSDLView touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        if (touch.view != self) return;
    }
    [self.targetSDLView touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        if (touch.view != self) return;
    }
    [self.targetSDLView touchesCancelled:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        if (touch.view != self) return;
    }
    [self.targetSDLView touchesMoved:touches withEvent:event];
}

@end

@interface MenubarViewController ()
@end

@implementation MenubarViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
}

-(void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    NSLog(@"self.view.frame = %@", NSStringFromCGRect(self.view.frame));
}

-(void)setupViews {
    self.view.backgroundColor = [UIColor clearColor];
    MenubarBackgroundView *backView = [[MenubarBackgroundView alloc] initWithFrame:(CGRectZero)];
    backView.targetSDLView = self.presentingViewController.view;
    CVCreate.withView(backView).addToView(self.view)
        .widthAnchor(self.view.widthAnchor, 0)
        .heightAnchor(self.view.heightAnchor, 0)
        .centerXAnchor(self.view.centerXAnchor, 0)
        .centerYAnchor(self.view.centerYAnchor, 0)
        .click(self, @selector(dismiss:));
    
    NSArray *(^CreateMenuItem)(NSString *, NSString *) = ^NSArray *(NSString *iconName, NSString *title) {
        return @[
            CVCreate.UIView.size(CGSizeMake(70, 10)),
            CVCreate.UIImageView([UIImage imageNamed:iconName])
                .customView(^(UIImageView *view){
                    view.contentMode = UIViewContentModeCenter;
                }),
            CVCreate.UILabel.text(title).fontSize(13)
                .textColor(UIColor.whiteColor)
                .textAlignment(NSTextAlignmentCenter),
            CVCreate.UIView,
        ];
    };
    
    CVCreate.UIStackView(@[
        CVCreate.UIView,
        CVCreate.UIStackView(CreateMenuItem(@"BackIcon", @"Back")).axis(UILayoutConstraintAxisVertical)
            .click(self, @selector(sendBackButton:)),
        CVCreate.UIView,
        CVCreate.UIStackView(CreateMenuItem(@"HomeIcon", @"Home")).axis(UILayoutConstraintAxisVertical)
            .click(self, @selector(sendHomeButton:)),
        CVCreate.UIView,
        CVCreate.UIStackView(CreateMenuItem(@"SwitchAppIcon", @"Switch")).axis(UILayoutConstraintAxisVertical)
            .click(self, @selector(sendSwitchAppButton:)),
        CVCreate.UIView,
        CVCreate.UIStackView(CreateMenuItem(@"KeyboardIcon", @"Keyboard")).axis(UILayoutConstraintAxisVertical)
            .click(self, @selector(showKeyboard:)),
        CVCreate.UIView,
        CVCreate.UIStackView(CreateMenuItem(@"DisconnectIcon", @"Stop")).axis(UILayoutConstraintAxisVertical)
            .click(self, @selector(sendDisconnectButton:)),
        CVCreate.UIView,
    ]).axis(UILayoutConstraintAxisHorizontal)
    .distribution(UIStackViewDistributionEqualCentering)
    .backgroundColor([UIColor colorWithWhite:0 alpha:0.85])
    .size(CGSizeMake(0, 80))
    .addToView(backView)
    .click(self, @selector(doNothing))
    .centerXAnchor(backView.centerXAnchor, 0)
    .widthAnchor(backView.widthAnchor, 0)
    .bottomAnchor(backView.bottomAnchor, 0);
}

-(void)doNothing {}

-(void)dismiss:(UITapGestureRecognizer *)gesture {
    SDL_StopTextInput();
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

-(void)showKeyboard:(UITapGestureRecognizer *)tap {
    NSLog(@"Showing keyboard");
    SDL_StartTextInput();
}

-(void)sendDisconnectButton:(UITapGestureRecognizer *)tap {
    [self clickAnimated:tap];
    [ScrcpySharedClient stopScrcpy];
}

@end
