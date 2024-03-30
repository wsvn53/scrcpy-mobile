//
//  UICommonUtils.h
//  scrcpy-ios
//
//  Created by Ethan on 26/2/23.
//

#ifndef UICommonUtils_h
#define UICommonUtils_h

#import <UIKit/UIKit.h>
#import "ScrcpySwitch.h"

#define is_dark_mode (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)

static inline UIColor *DynamicTintColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
        return is_dark_mode ? UIColor.whiteColor : UIColor.blackColor;
    }];
}

static inline UIColor *DynamicTextFieldBorderColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
        return is_dark_mode ? UIColor.whiteColor : [UIColor colorWithRed:0 green:0 blue:0 alpha:0.3];
    }];
}

static inline UIColor *DynamicTextColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
        return is_dark_mode ? UIColor.whiteColor : UIColor.darkGrayColor;
    }];
}

static inline UIColor *DynamicBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
        return is_dark_mode ? UIColor.darkGrayColor : UIColor.whiteColor;
    }];
}

static inline NSAttributedString *DynamicColoredPlaceholder(NSString *text) {
    UIColor *dynamicColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            return is_dark_mode ? UIColor.lightGrayColor : UIColor.grayColor;
    }];
    return [[NSAttributedString alloc] initWithString:text attributes:@{ NSForegroundColorAttributeName: dynamicColor}];
}

static inline void SetupViewControllerAppearance(UIViewController *vc) {
    // Enable dark mode
    vc.view.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
        return (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) ? [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0] : [UIColor whiteColor];
    }];
    
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor systemGray6Color];
        vc.navigationController.navigationBar.standardAppearance = appearance;
        vc.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    }
}

static inline void ShowAlertFrom(UIViewController *fromController,
                                 NSString *message,
                                 UIAlertAction *okAction,
                                 UIAlertAction *cancelAction) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Scrcpy Remote" message:message preferredStyle:(UIAlertControllerStyleAlert)];
    
    if (okAction) [alert addAction:okAction];
    if (cancelAction) [alert addAction:cancelAction];
    
    if (!okAction && !cancelAction) {
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:(UIAlertActionStyleCancel) handler:nil]];
    }
    [fromController presentViewController:alert animated:YES completion:nil];
}

static inline CVCreate *CreateDarkButton(NSString *title, id target, SEL action) {
    UIColor *borderColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
        return is_dark_mode ? UIColor.grayColor : UIColor.blackColor;
    }];
    return CVCreate.UIButton.text(title)
        .boldFontSize(16)
        .size(CGSizeMake(0, 45))
        .textColor(UIColor.whiteColor)
        .backgroundColor(UIColor.blackColor)
        .border(borderColor, 2.f)
        .cornerRadius(6)
        .click(target, action);
}

static inline CVCreate *CreateLightButton(NSString *title, id target, SEL action) {
    return CVCreate.UIButton.text(title)
        .boldFontSize(16)
        .size(CGSizeMake(0, 45))
        .textColor(UIColor.blackColor)
        .backgroundColor(UIColor.whiteColor)
        .border(UIColor.darkGrayColor, 2.f)
        .cornerRadius(6)
        .click(target, action);
}

static inline CVCreate *CreateScrcpySwitch(NSString *title, NSString *optionKey, void (^bindBlock)(ScrcpySwitch *view)) {
    return CVCreate.UIStackView(@[
        CVCreate.UILabel.text(title)
            .fontSize(16.f).textColor([UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
                return traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? UIColor.whiteColor : UIColor.blackColor;
            }]),
        CVCreate.create(ScrcpySwitch.class)
            .customView(^(ScrcpySwitch *view){
                view.optionKey = optionKey;
                bindBlock(view);
            }),
    ]).spacing(10.f);
}

#endif /* UICommonUtils_h */
