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

static NSString * kScrcpyADBHostKeychain = @"kScrcpyADBHostKeychain";
static NSString * kScrcpyADBPortKeychain = @"kScrcpyADBPortKeychain";

@interface ViewController ()
@property (nonatomic, weak)   UITextField *adbHost;
@property (nonatomic, weak)   UITextField *adbPort;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
}

-(void)setupViews {
    self.view.backgroundColor = UIColor.whiteColor;
    
    __weak typeof(self) _self = self;
    CVCreate.UIStackView(@[
        CVCreate.UIView.size(CGSizeMake(0, 50)),
        CVCreate.UILabel.text(@"Scrcpy Beta").boldFontSize(20)
            .textColor(UIColor.blackColor)
            .textAlignment(NSTextAlignmentCenter),
        CVCreate.create(UITextField.class).size(CGSizeMake(180, 40))
            .fontSize(16)
            .border(UIColor.blackColor, 1.f)
            .text([KFKeychain loadObjectForKey:kScrcpyADBHostKeychain])
            .customView(^(UITextField *view){
                view.placeholder = @"ADB Host";
                _self.adbHost = view;
            }),
        CVCreate.create(UITextField.class).size(CGSizeMake(180, 40))
            .fontSize(16)
            .border(UIColor.blackColor, 1.f)
            .text([KFKeychain loadObjectForKey:kScrcpyADBPortKeychain])
            .customView(^(UITextField *view){
                view.placeholder = @"ADB Port";
                _self.adbPort = view;
            }),
        CVCreate.UIButton.text(@"Connect").boldFontSize(16)
            .addToView(self.view)
            .size(CGSizeMake(180, 40))
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

-(void)start {
    [self.adbPort endEditing:YES];
    [self.adbHost endEditing:YES];
    
    if (self.adbHost.text.length == 0 || self.adbPort.text.length == 0) {
        return;
    }
    
    [KFKeychain saveObject:self.adbHost.text forKey:kScrcpyADBHostKeychain];
    [KFKeychain saveObject:self.adbPort.text forKey:kScrcpyADBPortKeychain];

    [ScrcpySharedClient startWith:self.adbHost.text adbPort:self.adbPort.text options:@[
         @"--verbosity=verbose", @"-f", @"--display-buffer=16",
         @"--max-fps=60", @"--stay-awake", @"--bit-rate=4M"
    ]];
}

@end
