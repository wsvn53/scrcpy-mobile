//
//  ViewController.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/2.
//

#import "ViewController.h"
#import "CVCreate.h"
#import "ScrcpyClient.h"
#import "KFKeychain.h"
#import "MBProgressHUD.h"
#import "ScrcpyTextField.h"
#import "ScrcpySwitch.h"
#import "config.h"

@interface ViewController ()

@property (nonatomic, weak)   ScrcpyTextField *adbHost;
@property (nonatomic, weak)   ScrcpyTextField *adbPort;
@property (nonatomic, weak)   ScrcpyTextField *maxSize;
@property (nonatomic, weak)   ScrcpyTextField *bitRate;
@property (nonatomic, weak)   ScrcpyTextField *maxFps;

@property (nonatomic, weak)   ScrcpySwitch  *turnScreenOff;
@property (nonatomic, weak)   ScrcpySwitch  *stayAwake;
@property (nonatomic, weak)   ScrcpySwitch  *forceAdbForward;
@property (nonatomic, weak)   ScrcpySwitch  *turnOffOnClose;

@property (nonatomic, weak)   UITextField *editingText;

@end

@implementation ViewController

-(void)loadView {
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:(CGRectZero)];
    scrollView.alwaysBounceVertical = YES;
    self.view = scrollView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
    [self setupEvents];
    [self setupClient];
    [self startADBServer];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [ScrcpySharedClient checkStartScheme];
}

-(void)startADBServer {
    [ScrcpySharedClient startADBServer];
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

-(void)setupViews {
    self.title = @"Scrcpy Beta";
    self.view.backgroundColor = UIColor.whiteColor;
    
    __weak typeof(self) _self = self;
    CVCreate.UIStackView(@[
        CVCreate.UIView.size(CGSizeMake(0, 5)),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"adb-host";
                view.placeholder = @"ADB Host";
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                if (@available(iOS 13.0, *)) {
                    view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                }
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.adbHost = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"adb-port";
                view.placeholder = @"ADB Port, Default 5555";
                if (@available(iOS 13.0, *)) {
                    view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                }
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.adbPort = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"max-size";
                view.placeholder = @"--max-size, Default Unlimited";
                if (@available(iOS 13.0, *)) {
                    view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                }
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.maxSize = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"bit-rate";
                view.placeholder = @"--bit-rate, Default 4M";
                if (@available(iOS 13.0, *)) {
                    view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                }
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.bitRate = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"max-fps";
                view.placeholder = @"--max-fps, Default 60";
                if (@available(iOS 13.0, *)) {
                    view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                }
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.maxFps = view;
            }),
        CVCreate.UIStackView(@[
            CVCreate.UILabel.text(@"Turn Screen Off:")
                .fontSize(16.f).textColor(UIColor.blackColor),
            CVCreate.create(ScrcpySwitch.class)
                .customView(^(ScrcpySwitch *view){
                    view.optionKey = @"turn-screen-off";
                    self.turnScreenOff = view;
                }),
        ]).spacing(10.f),
        CVCreate.UIStackView(@[
            CVCreate.UILabel.text(@"Stay Awake:")
                .fontSize(16.f).textColor(UIColor.blackColor),
            CVCreate.create(ScrcpySwitch.class)
                .customView(^(ScrcpySwitch *view){
                    view.optionKey = @"stay-awake";
                    self.stayAwake = view;
                }),
        ]).spacing(10.f),
        CVCreate.UIStackView(@[
            CVCreate.UILabel.text(@"Force ADB Forward:")
                .fontSize(16.f).textColor(UIColor.blackColor),
            CVCreate.create(ScrcpySwitch.class)
                .customView(^(ScrcpySwitch *view){
                    view.optionKey = @"force-adb-forward";
                    self.forceAdbForward = view;
                }),
        ]).spacing(10.f),
        CVCreate.UIStackView(@[
            CVCreate.UILabel.text(@"Turn Off When Closing:")
                .fontSize(16.f).textColor(UIColor.blackColor),
            CVCreate.create(ScrcpySwitch.class)
                .customView(^(ScrcpySwitch *view){
                    view.optionKey = @"power-off-on-close";
                    self.turnOffOnClose = view;
                }),
        ]).spacing(10.f),
        CVCreate.UIButton.text(@"Connect").boldFontSize(16)
            .addToView(self.view)
            .size(CGSizeMake(0, 45))
            .textColor(UIColor.whiteColor)
            .backgroundColor(UIColor.blackColor)
            .cornerRadius(6)
            .click(self, @selector(start)),
        CVCreate.UIButton.text(@"Copy URL Scheme").boldFontSize(16)
            .addToView(self.view)
            .size(CGSizeMake(0, 45))
            .textColor(UIColor.blackColor)
            .backgroundColor(UIColor.whiteColor)
            .border(UIColor.grayColor, 2.f)
            .cornerRadius(6)
            .click(self, @selector(copyURLScheme)),
        CVCreate.UILabel.fontSize(13.f).textColor(UIColor.grayColor)
            .text([NSString stringWithFormat:@"Based on scrcpy v%s", SCRCPY_VERSION])
            .textAlignment(NSTextAlignmentCenter),
        CVCreate.UIView,
    ]).axis(UILayoutConstraintAxisVertical).spacing(20.f)
    .addToView(self.view)
    .centerXAnchor(self.view.centerXAnchor, 0)
    .topAnchor(self.view.topAnchor, 0)
    .widthAnchor(self.view.widthAnchor, -30);
}

-(void)setupClient {
    __weak typeof(self) _self = self;
    
    ScrcpySharedClient.onADBConnecting = ^(NSString * _Nonnull serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_self showHUDWith:@"ADB\nConnecting"];
        });
    };
    
    ScrcpySharedClient.onADBConnected = ^(NSString *serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_self showHUDWith:@"ADB\nConnected"];
        });
    };
    
    ScrcpySharedClient.onADBConnectFailed = ^(NSString * _Nonnull serial, NSString * _Nonnull message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:_self.view animated:YES];
            [_self showAlert:[NSString stringWithFormat:@"ADB Connect Failed:\n%@", message]];
        });
    };
    
    ScrcpySharedClient.onADBUnauthorized = ^(NSString * _Nonnull serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *message = [NSString stringWithFormat:@"Device [%@] connected, but unahtorized. Please accept authorization on your device.", serial];
            [_self performSelectorOnMainThread:@selector(showAlert:) withObject:message waitUntilDone:NO];
        });
    };
    
    ScrcpySharedClient.onScrcpyConnectFailed = ^(NSString * _Nonnull serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:_self.view animated:YES];
            [_self showAlert:@"Start Scrcpy Failed"];
        });
    };
    
    ScrcpySharedClient.onScrcpyConnected = ^(NSString * _Nonnull serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_self showHUDWith:@"Scrcpy\nConnected"];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:_self.view animated:YES];
        });
    };
}

-(void)showAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Scrcpy" message:message preferredStyle:(UIAlertControllerStyleAlert)];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:(UIAlertActionStyleCancel) handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
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

-(void)stopEditing {
    [self.adbPort endEditing:YES];
    [self.adbHost endEditing:YES];
    [self.maxSize endEditing:YES];
    [self.bitRate endEditing:YES];
    [self.maxFps endEditing:YES];
}

-(void)start {
    [self stopEditing];
    
    if (self.adbHost.text.length == 0) {
        [self showAlert:@"ADB Host is required"];
        return;
    }
    
    [self.adbHost updateOptionValue];
    [self.adbPort updateOptionValue];
     
    NSArray *options = ScrcpySharedClient.defaultScrcpyOptions;
    
    NSArray * (^updateTextOptions)(NSArray *, ScrcpyTextField *) = ^NSArray * (NSArray *options, ScrcpyTextField *t) {
        [t updateOptionValue];
        if (t.text.length == 0) return options;
        return [ScrcpySharedClient setScrcpyOption:options name:t.optionKey value:t.text];
    };
    
    options = updateTextOptions(options, self.maxSize);
    options = updateTextOptions(options, self.bitRate);
    options = updateTextOptions(options, self.maxFps);
    
    NSArray * (^updateSwitchOptions)(NSArray *options, ScrcpySwitch *) = ^NSArray * (NSArray *options, ScrcpySwitch *s) {
        [s updateOptionValue];
        if (s.on == NO) return options;
        return [ScrcpySharedClient setScrcpyOption:options name:s.optionKey value:@""];
    };
    
    options = updateSwitchOptions(options, self.turnScreenOff);
    options = updateSwitchOptions(options, self.stayAwake);
    options = updateSwitchOptions(options, self.forceAdbForward);
    options = updateSwitchOptions(options, self.turnOffOnClose);
    
    [self showHUDWith:@"Starting.."];
    [ScrcpySharedClient startWith:self.adbHost.text adbPort:self.adbPort.text options:options];
}

-(void)copyURLScheme {
    [self stopEditing];
    
    NSURLComponents *urlComps = [[NSURLComponents alloc] initWithString:@"scrcpy2://"];
    urlComps.queryItems = [NSArray array];
    urlComps.host = self.adbHost.text;
    
    if (self.adbPort.text.length > 0) {
        urlComps.port = @([self.adbPort.text integerValue]);
    }
    
    // Assemble text options
    NSArray *(^updateURLTextItems)(NSArray *, ScrcpyTextField *) = ^NSArray *(NSArray *items, ScrcpyTextField *t) {
        if (t.text.length == 0) return items;
        NSURLQueryItem *item = [NSURLQueryItem queryItemWithName:t.optionKey value:t.text];
        return [items arrayByAddingObject:item];
    };
    
    urlComps.queryItems = updateURLTextItems(urlComps.queryItems, self.maxSize);
    urlComps.queryItems = updateURLTextItems(urlComps.queryItems, self.bitRate);
    urlComps.queryItems = updateURLTextItems(urlComps.queryItems, self.maxFps);
    
    // Assemble bool options
    NSArray *(^updateURLBoolItems)(NSArray *, ScrcpySwitch *) = ^NSArray *(NSArray *items, ScrcpySwitch *s) {
        if (s.on == NO) return items;
        NSURLQueryItem *item = [NSURLQueryItem queryItemWithName:s.optionKey value:@"true"];
        return [items arrayByAddingObject:item];
    };
    
    urlComps.queryItems = updateURLBoolItems(urlComps.queryItems, self.turnScreenOff);
    urlComps.queryItems = updateURLBoolItems(urlComps.queryItems, self.stayAwake);
    urlComps.queryItems = updateURLBoolItems(urlComps.queryItems, self.forceAdbForward);
    urlComps.queryItems = updateURLBoolItems(urlComps.queryItems, self.turnOffOnClose);
    
    // If no options, avoid "?"
    if (urlComps.queryItems.count == 0) {
        urlComps.queryItems = nil;
    }
    
    NSLog(@"URL: %@", urlComps.URL);
    [[UIPasteboard generalPasteboard] setURL:urlComps.URL];
    [self showAlert:[NSString stringWithFormat:@"Copied URL:\n%@", urlComps.URL.absoluteString]];
}

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
