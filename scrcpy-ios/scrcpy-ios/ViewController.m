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

static NSString * kScrcpyADBHostKeychain = @"kScrcpyADBHostKeychain";
static NSString * kScrcpyADBPortKeychain = @"kScrcpyADBPortKeychain";
static NSString * kScrcpyMaxSizeKeychain = @"kScrcpyMaxSizeKeychain";
static NSString * kScrcpyBitRateKeychain = @"kScrcpyBitRateKeychain";

@interface ViewController ()
@property (nonatomic, weak)   UITextField *adbHost;
@property (nonatomic, weak)   UITextField *adbPort;
@property (nonatomic, weak)   UITextField *maxSize;
@property (nonatomic, weak)   UITextField *bitRate;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
    [self setupClient];
    [self startADBServer];
}

-(void)startADBServer {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString *message = @"";
        BOOL success = [ScrcpySharedClient adbExecute:@[@"start-server"] message:&message];
        NSLog(@"Start ADB Server: %@", success?@"YES":@"NO");
        if (message.length > 0) printf("-> %s\n", message.UTF8String);
    });
}

-(void)setupViews {
    self.view.backgroundColor = UIColor.whiteColor;
    
    __weak typeof(self) _self = self;
    CVCreate.UIStackView(@[
        CVCreate.UIView.size(CGSizeMake(0, 50)),
        CVCreate.UILabel.text(@"Scrcpy Beta").boldFontSize(20)
            .textColor(UIColor.blackColor)
            .textAlignment(NSTextAlignmentCenter),
        CVCreate.create(UITextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border(UIColor.blackColor, 1.f)
            .text([KFKeychain loadObjectForKey:kScrcpyADBHostKeychain])
            .customView(^(UITextField *view){
                view.placeholder = @"ADB Host";
                _self.adbHost = view;
            }),
        CVCreate.create(UITextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border(UIColor.blackColor, 1.f)
            .text([KFKeychain loadObjectForKey:kScrcpyADBPortKeychain])
            .customView(^(UITextField *view){
                view.placeholder = @"ADB Port";
                _self.adbPort = view;
            }),
        CVCreate.create(UITextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border(UIColor.blackColor, 1.f)
            .text([KFKeychain loadObjectForKey:kScrcpyMaxSizeKeychain])
            .customView(^(UITextField *view){
                view.placeholder = @"Max Size";
                _self.maxSize = view;
            }),
        CVCreate.create(UITextField.class).size(CGSizeMake(0, 40))
            .fontSize(16)
            .border(UIColor.blackColor, 1.f)
            .text([KFKeychain loadObjectForKey:kScrcpyBitRateKeychain])
            .customView(^(UITextField *view){
                view.placeholder = @"BitRate, Default 4M";
                _self.bitRate = view;
            }),
        CVCreate.UIButton.text(@"Connect").boldFontSize(16)
            .addToView(self.view)
            .size(CGSizeMake(0, 40))
            .textColor(UIColor.whiteColor)
            .backgroundColor(UIColor.blackColor)
            .cornerRadius(6)
            .click(self, @selector(start)),
        CVCreate.UIView,
    ]).axis(UILayoutConstraintAxisVertical).spacing(20.f)
    .addToView(self.view)
    .centerXAnchor(self.view.centerXAnchor, 0)
    .centerYAnchor(self.view.centerYAnchor, 0)
    .widthAnchor(self.view.widthAnchor, -30)
    .heightAnchor(self.view.heightAnchor, -80);
}

-(void)setupClient {
    __weak typeof(self) _self = self;
    
    ScrcpySharedClient.onADBConnected = ^(NSString *serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [MBProgressHUD HUDForView:_self.view].label.text = @"ADB\nConnected";
        });
    };
    
    ScrcpySharedClient.onADBUnauthorized = ^(NSString * _Nonnull serial) {
        NSString *message = [NSString stringWithFormat:@"Device [%@] connected, but unahtorized. Please accept authorization on your device.", serial];
        [_self performSelectorOnMainThread:@selector(showAlert:) withObject:message waitUntilDone:NO];
    };
    
    ScrcpySharedClient.onScrcpyConnectFailed = ^(NSString * _Nonnull serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:_self.view animated:YES];
            [_self showAlert:@"Start Scrcpy Failed"];
        });
    };
    
    ScrcpySharedClient.onScrcpyConnected = ^(NSString * _Nonnull serial) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [MBProgressHUD HUDForView:_self.view].label.text = @"Scrcpy\nConnected";
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:_self.view animated:YES];
        });
    };
}

-(void)showAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Scrcpy" message:message preferredStyle:(UIAlertControllerStyleAlert)];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:(UIAlertActionStyleCancel) handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

-(void)start {
    [self.adbPort endEditing:YES];
    [self.adbHost endEditing:YES];
    [self.maxSize endEditing:YES];
    [self.bitRate endEditing:YES];
    
    if (self.adbHost.text.length == 0 || self.adbPort.text.length == 0) {
        return;
    }
     
    NSArray *options = @[
         @"--verbosity=verbose", @"--fullscreen", @"--display-buffer=32",
         @"--max-fps=60", @"--stay-awake", @"--turn-screen-off", @"--print-fps",
    ];
    
    if (self.maxSize.text.length > 0) {
        options = [options arrayByAddingObject:[NSString stringWithFormat:@"--max-size=%@", self.maxSize.text]];
    }
    
    NSString *bitRate = @"4M";
    if (self.bitRate.text.length > 0) { bitRate = self.bitRate.text; }
    options = [options arrayByAddingObject:[NSString stringWithFormat:@"--bit-rate=%@", bitRate]];
    
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.label.text = @"ADB\nConnecting";
    hud.label.numberOfLines = 2;
    hud.minSize = CGSizeMake(125, 125);
    
    [KFKeychain saveObject:self.adbHost.text forKey:kScrcpyADBHostKeychain];
    [KFKeychain saveObject:self.adbPort.text forKey:kScrcpyADBPortKeychain];
    [KFKeychain saveObject:self.maxSize.text forKey:kScrcpyMaxSizeKeychain];
    [KFKeychain saveObject:self.bitRate.text forKey:kScrcpyBitRateKeychain];

    [ScrcpySharedClient startWith:self.adbHost.text adbPort:self.adbPort.text options:options];
}

@end
