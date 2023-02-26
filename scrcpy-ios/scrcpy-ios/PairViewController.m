//
//  PairViewController.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/7/18.
//

#import "PairViewController.h"
#import "CVCreate.h"
#import "ScrcpyTextField.h"
#import "ScrcpyClient.h"
#import "MBProgressHUD.h"

@interface PairViewController ()
// TextFields
@property (nonatomic, weak)   UITextField   *pairingAddress;
@property (nonatomic, weak)   UITextField   *pairingPort;
@property (nonatomic, weak)   UITextField   *pairingCode;

@property (nonatomic, weak)   UITextField *editingText;

@end

@implementation PairViewController

-(void)loadView {
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:(CGRectZero)];
    scrollView.alwaysBounceVertical = YES;
    self.view = scrollView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
    [self setupEvents];
}

-(void)setupViews {
    self.view.backgroundColor = UIColor.whiteColor;
    self.title = NSLocalizedString(@"ADB Pair With Android", nil);
    
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor systemGray6Color];
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    }
    
    __weak typeof(self) _self = self;
    CVCreate.UIStackView(@[
        CVCreate.UIView.size(CGSizeMake(0, 5)),
        CVCreate.UILabel.boldFontSize(15).textColor(UIColor.darkGrayColor)
            .text(NSLocalizedString(@"How To Pair With Android Devices:", nil)),
        CVCreate.UILabel.fontSize(15).textColor(UIColor.darkGrayColor)
            .customView(^(UILabel *view){ view.numberOfLines = 10; })
            .text(NSLocalizedString(@"1. Go to Settings -> System -> Developer Options\n2. Enable Wireless Debugging\n3. Pair device with pairing code", nil)),
        CVCreate.UILabel.boldFontSize(15).textColor(UIColor.darkGrayColor)
            .text(NSLocalizedString(@"Note: This feature only available on Android 11 and above!", nil))
            .customView(^(UILabel *view){ view.numberOfLines = 2; }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.placeholder = NSLocalizedString(@"ADB Pairing IP Address", nil);
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                if (@available(iOS 13.0, *)) {
                    view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                }
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.pairingAddress = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.placeholder = NSLocalizedString(@"ADB Pairing Port", nil);
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                if (@available(iOS 13.0, *)) {
                    view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                }
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.pairingPort = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.placeholder = NSLocalizedString(@"ADB Pairing Code", nil);
                if (@available(iOS 13.0, *)) {
                    view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                }
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.pairingCode = view;
            }),
        CVCreate.UIButton.text(NSLocalizedString(@"Start Pairing", nil)).boldFontSize(16)
            .addToView(self.view)
            .size(CGSizeMake(0, 45))
            .textColor(UIColor.whiteColor)
            .backgroundColor(UIColor.blackColor)
            .cornerRadius(6)
            .click(self, @selector(startPairing)),
        CVCreate.UIButton.text(NSLocalizedString(@"Cancel", nil)).boldFontSize(16)
            .addToView(self.view)
            .size(CGSizeMake(0, 45))
            .textColor(UIColor.blackColor)
            .backgroundColor(UIColor.whiteColor)
            .border(UIColor.grayColor, 2.f)
            .cornerRadius(6)
            .click(self, @selector(cancelPairing)),
        CVCreate.UIView,
    ]).axis(UILayoutConstraintAxisVertical).spacing(15.f)
    .addToView(self.view)
    .centerXAnchor(self.view.centerXAnchor, 0)
    .topAnchor(self.view.topAnchor, 0)
    .widthAnchor(self.view.widthAnchor, -30);
}

-(void)setupEvents {
    CVCreate.withView(self.view).click(self, @selector(stopEditing));
    
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardDidShow:)
                                               name:UIKeyboardDidShowNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillHide:)
                                               name:UIKeyboardWillHideNotification object:nil];
}

-(void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIScrollView *scrollView = (UIScrollView *)self.view;
    scrollView.contentSize = self.view.subviews.firstObject.frame.size;
}

#pragma mark - Events

-(void)keyboardDidShow:(NSNotification *)notification {
    CGRect keyboardRect = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSLog(@"Keyboard Rect: %@", NSStringFromCGRect(keyboardRect));
    
    CGRect textFrame = [self.editingText.superview convertRect:self.editingText.frame toView:self.view];
    NSLog(@"Text Rect: %@", NSStringFromCGRect(textFrame));
    CGFloat textOffset = CGRectGetMaxY(textFrame) - keyboardRect.origin.y;
    NSLog(@"Text Offset: %@", @(textOffset));
    
    if (textOffset <= 0) {
        return;
    }

    UIScrollView *rootView = (UIScrollView *)self.view;
    rootView.contentOffset = (CGPoint){0, textOffset};
}

-(void)keyboardWillHide:(NSNotification *)notification {
    UIScrollView *rootView = (UIScrollView *)self.view;
    [rootView scrollRectToVisible:(CGRect){0, 0, 1, 1} animated:YES];
}

-(void)stopEditing {
    [self.editingText endEditing:YES];
    [self.pairingAddress endEditing:YES];
    [self.pairingPort endEditing:YES];
    [self.pairingCode endEditing:YES];
}

-(void)startPairing {
    [self stopEditing];
    
    if ([self.pairingAddress.text length] == 0) {
        [self showAlert:NSLocalizedString(@"Pairing Address is Empty!", nil)];
        return;
    }
    
    if ([self.pairingAddress.text containsString:@":"] == NO &&
        [self.pairingPort.text length] == 0) {
        [self showAlert:NSLocalizedString(@"Pairing Port is Empty", nil)];
        return;
    }
    
    if ([self.pairingCode.text length] == 0) {
        [self showAlert:NSLocalizedString(@"Pairing Code is Empty!", nil)];
        return;
    }
    
    [self showHUDWith:NSLocalizedString(@"Pairing..", nil)];
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString *pairingMessage = nil;
        
        NSString *pairingAddress = self.pairingAddress.text;
        if ([pairingAddress containsString:@":"] == NO) {
            pairingAddress = [NSString stringWithFormat:@"%@:%@", pairingAddress, self.pairingPort.text];
        }
        BOOL success = [ScrcpySharedClient adbExecute:@[
            @"pair", pairingAddress, self.pairingCode.text,
        ] message:&pairingMessage];
        
        NSLog(@"Result: %@, %@", @(success), pairingMessage);
        pairingMessage = [NSString stringWithFormat:@"ADB Pairing\n%@",
                          pairingMessage];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:weakSelf.view animated:YES];
            [weakSelf showAlert:pairingMessage];
        });
    });
}

-(void)cancelPairing {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

-(void)showHUDWith:(NSString *)text {
    MBProgressHUD *hud = [MBProgressHUD HUDForView:self.view];
    if (hud == nil) {
        hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.minSize = CGSizeMake(130, 130);
    }
    hud.label.text = text;
    hud.label.numberOfLines = 2;
}

-(void)showAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Scrcpy Remote" message:message preferredStyle:(UIAlertControllerStyleAlert)];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:(UIAlertActionStyleCancel) handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self stopEditing];
    return NO;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    self.editingText = textField;
    return YES;
}

@end
