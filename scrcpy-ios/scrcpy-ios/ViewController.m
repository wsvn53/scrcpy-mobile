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
    
    self.view.backgroundColor = UIColor.redColor;
    [ScrcpySharedClient startWith:@"redmi.wsen.me" adbPort:@"5555" options:@[
         @"-f", @"--verbosity=verbose"
    ]];
}

@end
