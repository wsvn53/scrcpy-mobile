//
//  LogsViewController.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/7/20.
//

#import "LogsViewController.h"
#import "LogManager.h"
#import "CVCreate.h"

@interface LogsViewController ()
@property (nonatomic, weak)     UITextView  *logsView;

@end

@implementation LogsViewController

#ifdef DEBUG
+(void)reload {
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.rootViewController.presentedViewController) {
            [window.rootViewController.presentedViewController dismissViewControllerAnimated:YES completion:nil];
        }
        if ([window.rootViewController isKindOfClass:UINavigationController.class]) {
            LogsViewController *vc = [[LogsViewController alloc] initWithNibName:nil bundle:nil];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            [window.rootViewController presentViewController:nav animated:YES completion:nil];
        }
    }
}
#endif

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
}

-(void)setupViews {
    self.title = @"Scrcpy Logs";
    self.view.backgroundColor = UIColor.whiteColor;
    
    // Refresh Logs
    UIBarButtonItem *refreshItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"Refresh"]
                                                                    style:(UIBarButtonItemStylePlain)
                                                                   target:self
                                                                   action:@selector(refreshLogs)];
    refreshItem.tintColor = UIColor.darkGrayColor;
    UIBarButtonItem *shareItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"Share"]
                                                                  style:(UIBarButtonItemStylePlain)
                                                                 target:self
                                                                 action:@selector(shareLogs)];
    shareItem.tintColor = UIColor.darkGrayColor;
    self.navigationItem.rightBarButtonItem = refreshItem;
    self.navigationItem.leftBarButtonItem = shareItem;
    
    CVCreate.UITextView.fontSize(15).textColor(UIColor.blackColor)
        .text(LogManager.sharedManager.recentLogs)
        .addToView(self.view)
        .leftAnchor(self.view.leftAnchor, 5)
        .rightAnchor(self.view.rightAnchor, -5)
        .topAnchor(self.view.topAnchor, 5)
        .bottomAnchor(self.view.bottomAnchor, -5)
        .customView(^(UITextView *view) {
            self.logsView = view;
            view.editable = NO;
        });
    
    [self refreshLogs];
}

#pragma mark - Events

-(void)refreshLogs {
    self.logsView.text = LogManager.sharedManager.recentLogs;
    [self.logsView scrollRangeToVisible:(NSRange){self.logsView.text.length-1, 1}];
}

-(void)shareLogs {
    NSArray *shareItems = @[ self.logsView.text ];
    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:shareItems applicationActivities:nil];
    activityViewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    [self presentViewController:activityViewController animated:YES completion:nil];
}

@end
