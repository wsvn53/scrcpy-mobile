//
//  ViewController.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/2.
//

#import "ViewController.h"
#import "PairViewController.h"
#import "KeysViewController.h"
#import "LogsViewController.h"
#import "CVCreate.h"
#import "ScrcpyClient.h"
#import "KFKeychain.h"
#import "MBProgressHUD.h"
#import "ScrcpyTextField.h"
#import "ScrcpySwitch.h"
#import "config.h"
#import "LogManager.h"
#import "UICommonUtils.h"
#import <MediaPlayer/MediaPlayer.h>

@interface ViewController ()

@property (nonatomic, weak)   ScrcpyTextField *adbHost;
@property (nonatomic, weak)   ScrcpyTextField *adbPort;
@property (nonatomic, weak)   ScrcpyTextField *maxSize;
@property (nonatomic, weak)   ScrcpyTextField *bitRate;
@property (nonatomic, weak)   ScrcpyTextField *maxFps;
@property (nonatomic, weak)   ScrcpyTextField *display;
@property (nonatomic, weak)   ScrcpyTextField *startApp;

@property (nonatomic, weak)   ScrcpySwitch  *turnScreenOff;
@property (nonatomic, weak)   ScrcpySwitch  *stayAwake;
@property (nonatomic, weak)   ScrcpySwitch  *forceAdbForward;
@property (nonatomic, weak)   ScrcpySwitch  *turnOffOnClose;
@property (nonatomic, weak)   ScrcpySwitch  *showNavButtons;
@property (nonatomic, weak)   ScrcpySwitch  *enableAudio;
@property (nonatomic, weak)   ScrcpySwitch  *enablePowerSavingMode;

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
    
    // Enable log redirect
#ifndef DEBUG
    [LogManager.sharedManager startHandleLog];
#endif
    
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
    self.title = @"Scrcpy Remote";
    
    // Setup appearance
    SetupViewControllerAppearance(self);
    
    // More button
    UIBarButtonItem *moreItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"More"] style:(UIBarButtonItemStylePlain) target:self action:@selector(showMoreMenu:)];
    moreItem.tintColor = DynamicTintColor();
    self.navigationItem.rightBarButtonItem = moreItem;
    
    __weak typeof(self) _self = self;
    CVCreate.UIStackView(@[
        CVCreate.UIView.size(CGSizeMake(0, 5)),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border(DynamicTextFieldBorderColor(), 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"adb-host";
                view.attributedPlaceholder = DynamicColoredPlaceholder(NSLocalizedString(@"ADB Host", nil));
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.adbHost = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border(DynamicTextFieldBorderColor(), 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"adb-port";
                view.attributedPlaceholder = DynamicColoredPlaceholder(NSLocalizedString(@"ADB Port, Default 5555", nil));
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.adbPort = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border(DynamicTextFieldBorderColor(), 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"max-size";
                view.attributedPlaceholder = DynamicColoredPlaceholder(NSLocalizedString(@"--max-size, Default Unlimited", nil));
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.maxSize = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border(DynamicTextFieldBorderColor(), 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"video-bit-rate";
                view.attributedPlaceholder = DynamicColoredPlaceholder(NSLocalizedString(@"--video-bit-rate, Default 4M", nil));
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.bitRate = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border(DynamicTextFieldBorderColor(), 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"max-fps";
                view.attributedPlaceholder = DynamicColoredPlaceholder(NSLocalizedString(@"--max-fps, Default 60", nil));
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.maxFps = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border(DynamicTextFieldBorderColor(), 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"new-display";
                view.attributedPlaceholder = DynamicColoredPlaceholder(NSLocalizedString(@"--new-display, format 1920x1080", nil));
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.display = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border(DynamicTextFieldBorderColor(), 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"start-app";
                view.attributedPlaceholder = DynamicColoredPlaceholder(NSLocalizedString(@"--start-app, format org.fossify.home", nil));
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.startApp = view;
            }),
        CreateScrcpySwitch(NSLocalizedString(@"Turn Screen Off:", nil),
            @"turn-screen-off",
            ^(ScrcpySwitch *view){
                self.turnScreenOff = view;
            }),
        CreateScrcpySwitch(NSLocalizedString(@"Stay Awake:", nil), 
            @"stay-awake",
            ^(ScrcpySwitch *view){
                self.stayAwake = view;
            }),
        CreateScrcpySwitch(NSLocalizedString(@"Force ADB Forward:", nil), 
            @"force-adb-forward",
            ^(ScrcpySwitch *view){
                self.forceAdbForward = view;
            }),
        CreateScrcpySwitch(NSLocalizedString(@"Turn Off When Closing:", nil), 
            @"power-off-on-close",
            ^(ScrcpySwitch *view){
                self.turnOffOnClose = view;
            }),
        CreateScrcpySwitch(NSLocalizedString(@"Always Show Navigation Buttons:", nil), 
            @"show-nav-buttons",
            ^(ScrcpySwitch *view){
                self.showNavButtons = view;
            }),
        CreateScrcpySwitch(NSLocalizedString(@"Enable Audio(Android 11+):", nil), 
            @"enable-audio", ^(ScrcpySwitch *view){
                self.enableAudio = view;
            }),
        CreateScrcpySwitch(NSLocalizedString(@"Power Saving Mode(for iPhone):", nil),
            @"power-saving", ^(ScrcpySwitch *view){
                self.enablePowerSavingMode = view;
            }),
        CreateDarkButton(NSLocalizedString(@"Connect", nil), self, @selector(start)),
        CreateLightButton(NSLocalizedString(@"Copy URL Scheme", nil), self, @selector(copyURLScheme)),
        CVCreate.UILabel.fontSize(13.f).textColor(UIColor.grayColor)
            .text(NSLocalizedString(@"For more help, please visit\nhttps://github.com/wsvn53/scrcpy-mobile", nil))
            .textAlignment(NSTextAlignmentCenter)
            .click(self, @selector(openScrcpyMobile))
            .customView(^(UILabel *view){
                view.numberOfLines = 2;
            }),
        CVCreate.UILabel.fontSize(13.f).textColor(UIColor.grayColor)
            .text([NSString stringWithFormat:@"Based on scrcpy v%s", SCRCPY_VERSION])
            .textAlignment(NSTextAlignmentCenter),
        CVCreate.UIView,
    ]).axis(UILayoutConstraintAxisVertical).spacing(12.f)
    .addToView(self.view)
    .centerXAnchor(self.view.centerXAnchor, 0)
    .topAnchor(self.view.topAnchor, 0)
    .widthAnchor(self.view.widthAnchor, -30);
}

-(void)setupClient {
    __weak typeof(self) weakSelf = self;
    
    ScrcpySharedClient.onADBConnecting = ^(NSString * _Nonnull serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf showHUDWith:NSLocalizedString(@"ADB\n🌐 Connecting", nil)];
        });
    };
    
    ScrcpySharedClient.onADBConnected = ^(NSString *serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf showHUDWith:NSLocalizedString(@"ADB\n✅ Connected!", nil)];
        });
    };
    
    ScrcpySharedClient.onADBConnectFailed = ^(NSString * _Nonnull serial, NSString * _Nonnull message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:weakSelf.view animated:YES];
            [weakSelf showAlert:[NSString stringWithFormat:NSLocalizedString(@"ADB Connect Failed:\n%@", nil), message]];
        });
    };
    
    ScrcpySharedClient.onADBUnauthorized = ^(NSString * _Nonnull serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Device [%@] connected, but unahtorized. Please accept authorization on your device.", nil), serial];
            [weakSelf performSelectorOnMainThread:@selector(showAlert:) withObject:message waitUntilDone:NO];
        });
    };
    
    ScrcpySharedClient.onScrcpyConnectFailed = ^(NSString * _Nonnull serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:weakSelf.view animated:YES];
            [weakSelf showAlert:NSLocalizedString(@"Start Scrcpy Failed", nil)];
        });
    };
    
    ScrcpySharedClient.onScrcpyConnected = ^(NSString * _Nonnull serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf showHUDWith:NSLocalizedString(@"Scrcpy\nConnected", nil)];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:weakSelf.view animated:YES];
        });
    };
}

-(void)showAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Scrcpy Remote" message:message preferredStyle:(UIAlertControllerStyleAlert)];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:(UIAlertActionStyleCancel) handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

-(void)showHUDWith:(NSString *)text {
    MBProgressHUD *hud = [MBProgressHUD HUDForView:self.view];
    if (hud == nil) {
        hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.minSize = CGSizeMake(130, 130);
    }
    hud.label.text = [text stringByAppendingString:@"\n[Click to Cancel]"];
    hud.label.font = [UIFont boldSystemFontOfSize:14.f];
    hud.label.numberOfLines = 3;
    hud.label.userInteractionEnabled = YES;
    [hud.label addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(stop)]];
}

-(void)stopEditing {
    [self.adbPort endEditing:YES];
    [self.adbHost endEditing:YES];
    [self.maxSize endEditing:YES];
    [self.bitRate endEditing:YES];
    [self.maxFps endEditing:YES];
    [self.display endEditing:YES];
    [self.startApp endEditing:YES];
}

-(void)stop {
    NSLog(@"User cacncelled connect.");
    [MBProgressHUD hideHUDForView:self.view animated:YES];
    [ScrcpySharedClient stopScrcpy];
}

-(void)start {
    [self stopEditing];
    
    if ([self.adbHost.text isEqualToString:@"vnc"] ||
        [self.adbPort.text isEqualToString:@"5900"]) {
        __weak typeof(self) weakSelf = self;
        [self switchVNCMode:^{
            [weakSelf finalStart];
        }];
        return;
    }
    
    [self finalStart];
}

-(void)finalStart {
    if (self.adbHost.text.length == 0) {
        [self showAlert:NSLocalizedString(@"ADB Host is required", nil)];
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
    options = updateTextOptions(options, self.display);
    options = updateTextOptions(options, self.startApp);
    
    NSArray * (^updateSwitchOptions)(NSArray *options, ScrcpySwitch *) = ^NSArray * (NSArray *options, ScrcpySwitch *s) {
        [s updateOptionValue];
        if (s.on == NO) return options;
        return [ScrcpySharedClient setScrcpyOption:options name:s.optionKey value:@""];
    };
    
    options = updateSwitchOptions(options, self.turnScreenOff);
    options = updateSwitchOptions(options, self.stayAwake);
    options = updateSwitchOptions(options, self.forceAdbForward);
    options = updateSwitchOptions(options, self.turnOffOnClose);
    options = updateSwitchOptions(options, self.showNavButtons);
    options = updateSwitchOptions(options, self.enableAudio);
    options = updateSwitchOptions(options, self.enablePowerSavingMode);
    
    ScrcpySharedClient.shouldAlwaysShowNavButtons = self.showNavButtons.on;
    ScrcpySharedClient.enablePowerSavingMode = self.enablePowerSavingMode.on;
    
    [self showHUDWith:NSLocalizedString(@"Starting..", nil)];
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
    urlComps.queryItems = updateURLTextItems(urlComps.queryItems, self.display);
    urlComps.queryItems = updateURLTextItems(urlComps.queryItems, self.startApp);
    
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
    urlComps.queryItems = updateURLBoolItems(urlComps.queryItems, self.showNavButtons);
    urlComps.queryItems = updateURLBoolItems(urlComps.queryItems, self.enableAudio);
    urlComps.queryItems = updateURLBoolItems(urlComps.queryItems, self.enablePowerSavingMode);
    
    // If no options, avoid "?"
    if (urlComps.queryItems.count == 0) {
        urlComps.queryItems = nil;
    }
    
    NSLog(@"URL: %@", urlComps.URL);
    [[UIPasteboard generalPasteboard] setURL:urlComps.URL];
    [self showAlert:[NSString stringWithFormat:NSLocalizedString(@"Copied URL:\n%@", nil), urlComps.URL.absoluteString]];
}

-(void)showMoreMenu:(UIBarButtonItem *)sender {
    NSLog(@"Show More Menu");
    UIAlertController *menuController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:(UIAlertControllerStyleActionSheet)];
    menuController.popoverPresentationController.sourceView = self.navigationController.navigationBar;
    CGRect sourceRect = self.navigationController.navigationBar.frame;
    sourceRect.origin.x = sourceRect.size.width - 50;
    sourceRect.size.width = 40;
    sourceRect.size.height = 40;
    menuController.popoverPresentationController.sourceRect = sourceRect;
    __weak typeof(self) weakSelf = self;
    [menuController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Pair with [Pairing Code]", nil) style:(UIAlertActionStyleDefault) handler:^(UIAlertAction *action) {
        NSLog(@"Start pair device controller");
        PairViewController *pairController = [[PairViewController alloc] initWithNibName:nil bundle:nil];
        UINavigationController *pairNav = [[UINavigationController alloc] initWithRootViewController:pairController];
        [weakSelf presentViewController:pairNav animated:YES completion:nil];
    }]];
    [menuController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Import/Export ADB keys", nil) style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        NSLog(@"Import/Export ADB keys");
        KeysViewController *keysController = [[KeysViewController alloc] initWithNibName:nil bundle:nil];
        UINavigationController *keysNav = [[UINavigationController alloc] initWithRootViewController:keysController];
        [weakSelf presentViewController:keysNav animated:YES completion:nil];
    }]];
    [menuController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Show detailed scrcpy logs", nil) style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        LogsViewController *logsController = [[LogsViewController alloc] initWithNibName:nil bundle:nil];
        UINavigationController *logsrNav = [[UINavigationController alloc] initWithRootViewController:logsController];
        [weakSelf presentViewController:logsrNav animated:YES completion:nil];
    }]];
    [menuController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Report an issue", nil) style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        NSLog(@"Report an issue");
        NSURL *issueLink = [NSURL URLWithString:@"https://github.com/wsvn53/scrcpy-mobile/issues"];
        [UIApplication.sharedApplication openURL:issueLink options:@{} completionHandler:nil];
    }]];
    [menuController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:(UIAlertActionStyleCancel) handler:^(UIAlertAction * _Nonnull action) {
        NSLog(@"Cancel");
    }]];
    [self presentViewController:menuController animated:YES completion:nil];
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

-(void)openScrcpyMobile {
    NSURL *projectLink = [NSURL URLWithString:@"https://github.com/wsvn53/scrcpy-mobile"];
    [UIApplication.sharedApplication openURL:projectLink options:@{} completionHandler:nil];
}

-(void)switchVNCMode:(void(^)(void))continueCompletion {
    UIAlertController *switchController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Switch Mode", nil) message:NSLocalizedString(@"Switching to VNC Mode?", nil) preferredStyle:UIAlertControllerStyleAlert];
    [switchController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes, Switch VNC Mode", nil) style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        // Switch to VNC mode
        NSURL *adbURL = [NSURL URLWithString:@"scrcpy2://vnc"];
        [UIApplication.sharedApplication openURL:adbURL options:@{} completionHandler:nil];
    }]];
    [switchController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No, Continue ADB Mode", nil) style:(UIAlertActionStyleCancel) handler:^(UIAlertAction * _Nonnull action) {
        continueCompletion();
    }]];
    
    [self presentViewController:switchController animated:YES completion:nil];
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
