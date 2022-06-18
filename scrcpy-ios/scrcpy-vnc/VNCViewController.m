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
    self.title = @"Scrcpy Remote VNC Client";
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
                view.placeholder = @"VNC Host Address";
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
                view.placeholder = @"VNC Port";
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
                view.placeholder = @"VNC Password, Optional";
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
            CVCreate.UILabel.text(@"Auto Connect:")
                .fontSize(16.f).textColor(UIColor.blackColor),
            CVCreate.create(ScrcpySwitch.class)
                .customView(^(ScrcpySwitch *view){
                    view.optionKey = @"vnc-auto-connect";
                    _self.autoConnect = view;
                }),
            ]).spacing(10.f),
        CVCreate.UIStackView(@[
            CVCreate.UILabel.text(@"View Only:")
                .fontSize(16.f).textColor(UIColor.blackColor),
            CVCreate.create(ScrcpySwitch.class)
                .customView(^(ScrcpySwitch *view){
                    view.optionKey = @"vnc-view-only";
                    _self.viewOnly = view;
                }),
            ]).spacing(10.f),
        CVCreate.UIStackView(@[
            CVCreate.UILabel.text(@"Full Screen:")
                .fontSize(16.f).textColor(UIColor.blackColor),
            CVCreate.create(ScrcpySwitch.class)
                .customView(^(ScrcpySwitch *view){
                    view.optionKey = @"vnc-full-screen";
                    _self.fullScreen = view;
                }),
            ]).spacing(10.f),
        CVCreate.UIButton.backgroundColor(UIColor.blackColor)
            .cornerRadius(5.f).text(@"Connect")
            .click(self, @selector(startVNCBrowser))
            .size(CGSizeMake(180, 40)),
        CVCreate.UILabel.text(@"Scrcpy Remote Currently Only Support VNC Port Over WebSocket.")
            .textColor(UIColor.grayColor)
            .fontSize(15.f)
            .textAlignment(NSTextAlignmentCenter)
            .customView(^(UILabel *view){
                view.numberOfLines = 2;
            }),
        CVCreate.UIView,
    ]).axis(UILayoutConstraintAxisVertical)
    .spacing(20.f)
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
    
    VNCBrowserViewController *browserController = [[VNCBrowserViewController alloc] initWithNibName:nil bundle:nil];
    NSURLComponents *vncComps = [NSURLComponents componentsWithString:@"http://127.0.0.1:25900/vnc.html"];
    vncComps.queryItems = [NSArray array];
    
    if (self.vncHost.text.length == 0) {
        [self showAlert:@"VNC Host is Required"];
        return;
    }
    vncComps.queryItems = [vncComps.queryItems arrayByAddingObject:[NSURLQueryItem queryItemWithName:@"host" value:self.vncHost.text]];
    
    if (self.vncPort.text.length == 0) {
        [self showAlert:@"VNC Port is Required"];
        return;
    }
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
    
    browserController.showsFullscreen = self.fullScreen.on;
    browserController.vncURL = [vncComps URL].absoluteString;
    browserController.title = [NSString stringWithFormat:@"Remote(%@)", self.vncHost.text];
    [self.navigationController pushViewController:browserController animated:YES];
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
