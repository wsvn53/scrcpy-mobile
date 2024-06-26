//
//  VNCViewController.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/15.
//

#import "VNCViewController.h"
#import "HTTPServer.h"
#import "VNCHTTPConnection.h"
#import "CVCreate.h"
#import "VNCBrowserViewController.h"

#import "ScrcpyTextField.h"
#import "ScrcpySwitch.h"

@interface VNCViewController ()

@property (nonatomic, strong)  NSOperationQueue *httpQueue;
@property (nonatomic, strong)  HTTPServer   *httpServer;

@property (nonatomic, weak)     ScrcpyTextField *vncHost;
@property (nonatomic, weak)     ScrcpyTextField *vncPort;
@property (nonatomic, weak)     ScrcpyTextField *vncPassword;

@property (nonatomic, weak)     ScrcpySwitch *autoConnect;
@property (nonatomic, weak)     ScrcpySwitch *viewOnly;
@property (nonatomic, weak)     ScrcpySwitch *fullScreen;

@property (nonatomic, weak)   UITextField *editingText;

@end

@implementation VNCViewController

-(void)loadView {
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:(CGRectZero)];
    scrollView.alwaysBounceVertical = YES;
    self.view = scrollView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
    [self setupEvents];
    [self startWebServer];
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:YES];
}

-(void)setupEvents {
    CVCreate.withView(self.view).click(self, @selector(stopEditing));
    
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardDidShow:)
                                               name:UIKeyboardDidShowNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillHide:)
                                               name:UIKeyboardWillHideNotification object:nil];
}

-(void)setupViews {
    self.title = NSLocalizedString(@"Scrcpy Remote VNC Client", nil);
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor systemGray6Color];
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    }
    self.view.backgroundColor = UIColor.whiteColor;
    
    __weak typeof(self) _self = self;
    CVCreate.UIStackView(@[
        CVCreate.UIView,
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"vnc-host";
                view.placeholder = NSLocalizedString(@"VNC Host or ADB Host", nil);
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                if (@available(iOS 13.0, *)) {
                    view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                }
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.vncHost = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"vnc-port";
                view.placeholder = NSLocalizedString(@"VNC Port or ADB Port", nil);
                if (@available(iOS 13.0, *)) {
                    view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                }
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                _self.vncPort = view;
            }),
        CVCreate.create(ScrcpyTextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border([UIColor colorWithRed:0 green:0 blue:0 alpha:0.3], 2.f)
            .cornerRadius(5.f)
            .customView(^(ScrcpyTextField *view){
                view.optionKey = @"vnc-password";
                view.placeholder = NSLocalizedString(@"VNC Password, Optional", nil);
                if (@available(iOS 13.0, *)) {
                    view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                }
                view.autocorrectionType = UITextAutocorrectionTypeNo;
                view.autocapitalizationType = UITextAutocapitalizationTypeNone;
                view.delegate = (id<UITextFieldDelegate>)_self;
                view.secureTextEntry = YES;
                _self.vncPassword = view;
            }),
        CVCreate.UIStackView(@[
            CVCreate.UILabel.text(NSLocalizedString(@"Auto Connect:", nil))
                .fontSize(16.f).textColor(UIColor.blackColor),
            CVCreate.create(ScrcpySwitch.class)
                .customView(^(ScrcpySwitch *view){
                    view.optionKey = @"vnc-auto-connect";
                    _self.autoConnect = view;
                }),
            ]).spacing(10.f),
        CVCreate.UIStackView(@[
            CVCreate.UILabel.text(NSLocalizedString(@"View Only:", nil))
                .fontSize(16.f).textColor(UIColor.blackColor),
            CVCreate.create(ScrcpySwitch.class)
                .customView(^(ScrcpySwitch *view){
                    view.optionKey = @"vnc-view-only";
                    _self.viewOnly = view;
                }),
            ]).spacing(10.f),
        CVCreate.UIStackView(@[
            CVCreate.UILabel.text(NSLocalizedString(@"Full Screen:", nil))
                .fontSize(16.f).textColor(UIColor.blackColor),
            CVCreate.create(ScrcpySwitch.class)
                .customView(^(ScrcpySwitch *view){
                    view.optionKey = @"vnc-full-screen";
                    _self.fullScreen = view;
                }),
            ]).spacing(10.f),
        CVCreate.UIButton.backgroundColor(UIColor.blackColor)
            .cornerRadius(5.f).text(NSLocalizedString(@"Connect", nil))
            .click(self, @selector(startVNCBrowser))
            .size(CGSizeMake(180, 40)),
        CVCreate.UILabel.text(NSLocalizedString(@"Scrcpy Remote currently only support VNC port over WebSocket. You can setup a websocket port by webcoskify https://github.com/novnc/websockify", nil))
            .click(self, @selector(openWebsockify))
            .textColor(UIColor.grayColor)
            .fontSize(15.f)
            .textAlignment(NSTextAlignmentCenter)
            .customView(^(UILabel *view){
                view.numberOfLines = 5;
            }),
        CVCreate.UIView,
    ]).axis(UILayoutConstraintAxisVertical)
    .spacing(15.f)
    .distribution(UIStackViewDistributionFill)
    .addToView(self.view)
    .widthAnchor(self.view.widthAnchor, -30)
    .centerXAnchor(self.view.centerXAnchor, 0)
    .topAnchor(self.view.topAnchor, 20);
}

-(void)startWebServer {
    self.httpServer = [[HTTPServer alloc] init];
    self.httpServer.connectionClass = VNCHTTPConnection.class;
    
    [self.httpServer setType:@"_http._tcp."];
    [self.httpServer setPort:25900];
    
    NSString *webPath = [[NSBundle mainBundle] bundlePath];
    [self.httpServer setDocumentRoot:webPath];
    
    __weak typeof(self) weakSelf = self;
    NSLog(@"-> Starting HTTPServer at :%d", self.httpServer.port);
    self.httpQueue = [[NSOperationQueue alloc] init];
    self.httpQueue.maxConcurrentOperationCount = 1;
    [self.httpQueue addOperationWithBlock:^{
        NSError *error;
        if(![weakSelf.httpServer start:&error]) {
            NSLog(@"Error starting HTTP Server: %@", error);
        }
    }];
}

-(void)showAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Scrcpy Remote" message:message preferredStyle:(UIAlertControllerStyleAlert)];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:(UIAlertActionStyleCancel) handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

-(void)startVNCBrowser {
    [self stopEditing];
    
    [self.vncHost updateOptionValue];
    [self.vncPort updateOptionValue];
    [self.vncPassword updateOptionValue];
    [self.autoConnect updateOptionValue];
    [self.viewOnly updateOptionValue];
    [self.fullScreen updateOptionValue];
    
    // Auto check HOST and PORT to switch adb mode
    if ([self.vncHost.text isEqualToString:@"adb"] ||
        [self.vncPort.text isEqualToString:@"5555"]) {
        __weak typeof(self) weakSelf = self;
        [self switchADBMode:^{
            [weakSelf finalStartVNCBrowser];
        }];
        return;
    }
    
    // Final
    [self finalStartVNCBrowser];
}

-(void)finalStartVNCBrowser {
    if (self.vncHost.text.length == 0) {
        [self showAlert:NSLocalizedString(@"VNC Host is Required", nil)];
        return;
    }
    
    if (self.vncPort.text.length == 0) {
        [self showAlert:NSLocalizedString(@"VNC Port is Required", nil)];
        return;
    }
    
    NSURLComponents *vncComps = [NSURLComponents componentsWithString:@"http://127.0.0.1:25900/vnc.html"];
    vncComps.queryItems = [NSArray array];
    vncComps.queryItems = [vncComps.queryItems arrayByAddingObject:[NSURLQueryItem queryItemWithName:@"host" value:self.vncHost.text]];
    vncComps.queryItems = [vncComps.queryItems arrayByAddingObject:[NSURLQueryItem queryItemWithName:@"port" value:self.vncPort.text]];
    
    if (self.vncPassword.text.length > 0) {
        vncComps.queryItems = [vncComps.queryItems arrayByAddingObject:[NSURLQueryItem queryItemWithName:@"password" value:self.vncPassword.text]];
    }
    
    if (self.autoConnect.on) {
        vncComps.queryItems = [vncComps.queryItems arrayByAddingObject:[NSURLQueryItem queryItemWithName:@"autoconnect" value:@"1"]];
    }
    
    if (self.viewOnly.on) {
        vncComps.queryItems = [vncComps.queryItems arrayByAddingObject:[NSURLQueryItem queryItemWithName:@"view_only" value:@"1"]];
    }
    
    VNCBrowserViewController *browserController = [[VNCBrowserViewController alloc] initWithNibName:nil bundle:nil];
    browserController.showsFullscreen = self.fullScreen.on;
    browserController.vncURL = [vncComps URL].absoluteString;
    browserController.title = [NSString stringWithFormat:@"Remote(%@)", self.vncHost.text];
    [self.navigationController pushViewController:browserController animated:YES];
}

-(void)openWebsockify {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/novnc/websockify"]
                                     options:@{}
                           completionHandler:nil];
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

-(void)stopEditing {
    [self.vncHost endEditing:YES];
    [self.vncPort endEditing:YES];
    [self.vncPassword endEditing:YES];
}

-(void)switchADBMode:(void(^)(void))continueCompletion {
    UIAlertController *switchController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Switch ADB Mode", nil) message:NSLocalizedString(@"Switching to ADB Mode?", nil) preferredStyle:UIAlertControllerStyleAlert];
    [switchController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes, Switch ADB Mode", nil) style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        // Switch to ADB mode
        NSURL *adbURL = [NSURL URLWithString:@"scrcpy2://adb"];
        [UIApplication.sharedApplication openURL:adbURL options:@{} completionHandler:nil];
    }]];
    [switchController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No, Continue VNC Mode", nil) style:(UIAlertActionStyleCancel) handler:^(UIAlertAction * _Nonnull action) {
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
