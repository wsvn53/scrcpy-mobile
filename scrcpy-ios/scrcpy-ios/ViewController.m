//
//  ViewController.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/2.
//

#import "ViewController.h"
#import "CVCreate.h"
#import "ScrcpyClient.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
}

-(void)setupViews {
    self.view.backgroundColor = UIColor.whiteColor;
    
    CVCreate.UIButton.text(@"Redmi Note 11 Pro").fontSize(16)
        .addToView(self.view)
        .size(CGSizeMake(180, 40))
        .centerXAnchor(self.view.centerXAnchor, 0)
        .centerYAnchor(self.view.centerYAnchor, -40)
        .textColor(UIColor.whiteColor)
        .backgroundColor(UIColor.blackColor)
        .cornerRadius(6)
        .click(self, @selector(startRedmi));
    
    CVCreate.UIButton.text(@"Pixel 4a").fontSize(16)
        .addToView(self.view)
        .size(CGSizeMake(180, 40))
        .centerXAnchor(self.view.centerXAnchor, 0)
        .centerYAnchor(self.view.centerYAnchor, 40)
        .textColor(UIColor.whiteColor)
        .backgroundColor(UIColor.blackColor)
        .cornerRadius(6)
        .click(self, @selector(startPixel));
}

-(void)startRedmi {
    [ScrcpySharedClient startWith:@"redmi.wsen.me" adbPort:@"5555" options:@[
         @"--verbosity=verbose", @"-f", @"--display-buffer=16",
         @"--max-fps=60", @"--stay-awake", @"--bit-rate=3M"
    ]];
}

-(void)startPixel {
    [ScrcpySharedClient startWith:@"pixel.wsen.me" adbPort:@"5555" options:@[
         @"--verbosity=verbose", @"-f", @"--display-buffer=16",
         @"--max-fps=60", @"--stay-awake", @"--bit-rate=4M"
    ]];
}

@end
