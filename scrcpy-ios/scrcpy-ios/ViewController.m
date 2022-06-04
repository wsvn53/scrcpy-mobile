//
//  ViewController.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/2.
//

#import "ViewController.h"
#import "ScrcpyClient.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(start)];
    [self.view addGestureRecognizer:tap];
}

-(void)setupViews {
    self.view.backgroundColor = UIColor.whiteColor;
}

-(void)start {
    [ScrcpySharedClient startWith:@"redmi.wsen.me" adbPort:@"5555" options:@[
         @"--verbosity=verbose", @"-f", @"--display-buffer=8", @"--max-fps=60", @"--stay-awake", @"--bit-rate=4M"
    ]];
}

@end
