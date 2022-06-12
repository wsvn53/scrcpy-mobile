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
#import "config.h"

static NSString * kScrcpyADBHostKeychain = @"kScrcpyADBHostKeychain";
static NSString * kScrcpyADBPortKeychain = @"kScrcpyADBPortKeychain";
static NSString * kScrcpyMaxSizeKeychain = @"kScrcpyMaxSizeKeychain";
static NSString * kScrcpyMaxFpsKeychain = @"kScrcpyMaxFpsKeychain";
static NSString * kScrcpyBitRateKeychain = @"kScrcpyBitRateKeychain";

@interface ViewController ()
@property (nonatomic, weak)   UITextField *adbHost;
@property (nonatomic, weak)   UITextField *adbPort;
@property (nonatomic, weak)   UITextField *maxSize;
@property (nonatomic, weak)   UITextField *bitRate;
@property (nonatomic, weak)   UITextField *maxFps;

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
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString *message = @"";
        BOOL success = [ScrcpySharedClient adbExecute:@[@"start-server"] message:&message];
        NSLog(@"Start ADB Server: %@", success?@"YES":@"NO");
        if (message.length > 0) printf("-> %s\n", message.UTF8String);
    });
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
    
    UINavigationBarAppearance *apperance = [[UINavigationBarAppearance alloc] init];
    apperance.backgroundColor = UIColor.systemGray6Color;
    apperance.titleTextAttributes = @{
        NSForegroundColorAttributeName: UIColor.blackColor,
    };
    self.navigationController.navigationBar.standardAppearance = apperance;
    self.navigationController.navigationBar.compactAppearance = apperance;
    self.navigationController.navigationBar.scrollEdgeAppearance = apperance;
    [self.navigationController setNeedsStatusBarAppearanceUpdate];
    
    __weak typeof(self) _self = self;
    CVCreate.UIStackView(@[
        CVCreate.UIView.size(CGSizeMake(0, 5)),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .text([KFKeychain loadObjectForKey:kScrcpyADBHostKeychain])
            .cornerRadius(5.f)
            .customView(^(UITextField *view){
                view.placeholder = @"ADB Host";
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.adbHost = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .text([KFKeychain loadObjectForKey:kScrcpyADBPortKeychain])
            .cornerRadius(5.f)
            .customView(^(UITextField *view){
                view.placeholder = @"ADB Port";
                view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.adbPort = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .text([KFKeychain loadObjectForKey:kScrcpyMaxSizeKeychain])
            .cornerRadius(5.f)
            .customView(^(UITextField *view){
                view.placeholder = @"--max-size, default unlimited";
                view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.maxSize = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .text([KFKeychain loadObjectForKey:kScrcpyBitRateKeychain])
            .cornerRadius(5.f)
            .customView(^(UITextField *view){
                view.placeholder = @"--bit-rate, default 4M";
                view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.bitRate = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .text([KFKeychain loadObjectForKey:kScrcpyMaxFpsKeychain])
            .cornerRadius(5.f)
            .customView(^(UITextField *view){
                view.placeholder = @"--max-fps, default 60";
                view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.maxFps = view;
            }),
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
            [_self showHUDWith:@"ADB\nconnecting"];
        });
    };
    
    ScrcpySharedClient.onADBConnected = ^(NSString *serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_self showHUDWith:@"ADB\nconnected"];
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
            [_self showHUDWith:@"Scrcpy\nconnected"];
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
    
    if (self.adbHost.text.length == 0 || self.adbPort.text.length == 0) {
        return;
    }
     
    NSArray *options = ScrcpySharedClient.defaultScrcpyOptions;
    if (self.maxSize.text.length > 0) {
        options = [ScrcpySharedClient setScrcpyOption:options name:@"max-size" value:self.maxSize.text];
    }
    
    if (self.bitRate.text.length > 0) {
        options = [ScrcpySharedClient setScrcpyOption:options name:@"bit-rate" value:self.bitRate.text];
    }
    
    if (self.maxFps.text.length > 0) {
        options = [ScrcpySharedClient setScrcpyOption:options name:@"max-fps" value:self.maxFps.text];
    }
    
    [KFKeychain saveObject:self.adbHost.text forKey:kScrcpyADBHostKeychain];
    [KFKeychain saveObject:self.adbPort.text forKey:kScrcpyADBPortKeychain];
    [KFKeychain saveObject:self.maxSize.text forKey:kScrcpyMaxSizeKeychain];
    [KFKeychain saveObject:self.bitRate.text forKey:kScrcpyBitRateKeychain];

    [self showHUDWith:@"ADB\nConnecting"];
    [ScrcpySharedClient startWith:self.adbHost.text adbPort:self.adbPort.text options:options];
}

-(void)copyURLScheme {
    [self stopEditing];
    
    NSURLComponents *urlComps = [[NSURLComponents alloc] initWithString:@"scrcpy2://"];
    urlComps.queryItems = [NSArray array];
    urlComps.host = self.adbHost.text;
    urlComps.port = @([self.adbPort.text integerValue]);
    
    if (self.maxSize.text.length > 0) {
        NSURLQueryItem *item = [NSURLQueryItem queryItemWithName:@"max-size" value:self.maxSize.text];
        urlComps.queryItems = [urlComps.queryItems arrayByAddingObject:item];
    }
    
    if (self.bitRate.text.length > 0) {
        NSURLQueryItem *item = [NSURLQueryItem queryItemWithName:@"bit-rate" value:self.bitRate.text];
        urlComps.queryItems = [urlComps.queryItems arrayByAddingObject:item];
    }
    
    if (self.maxFps.text.length > 0) {
        NSURLQueryItem *item = [NSURLQueryItem queryItemWithName:@"max-fps" value:self.bitRate.text];
        urlComps.queryItems = [urlComps.queryItems arrayByAddingObject:item];
    }
    
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
