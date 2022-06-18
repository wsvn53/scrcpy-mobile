//
//  VNCBrowserViewController.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/15.
//

#import "VNCBrowserViewController.h"
#import "CVCreate.h"
#import <WebKit/WKWebView.h>

@interface VNCBrowserViewController ()

@property (nonatomic, strong)   WKWebView   *webView;

@end

@implementation VNCBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
    [self loadVNCWithURL:[NSURL URLWithString:self.vncURL]];
}

-(void)setupViews {
    self.title = self.title.length > 0 ? self.title : @"Remote VNC";
    self.view.backgroundColor = UIColor.whiteColor;
    
    self.webView = [[WKWebView alloc] initWithFrame:(CGRectZero)];
    self.webView.navigationDelegate = (id<WKNavigationDelegate>)self;
    CVCreate.withView(self.webView).addToView(self.view)
        .centerXAnchor(self.view.centerXAnchor, 0)
        .centerYAnchor(self.view.centerYAnchor, 0)
        .widthAnchor(self.view.widthAnchor, 0)
        .heightAnchor(self.view.heightAnchor, 0);
    
    if (self.showsFullscreen) {
        [self.navigationController setNavigationBarHidden:YES animated:YES];
        CVCreate.UIImageView([UIImage imageNamed:@"disconnect"])
            .addToView(self.view)
            .backgroundColor(UIColor.grayColor)
            .cornerRadius(10)
            .rightAnchor(self.view.rightAnchor, -20)
            .topAnchor(self.view.topAnchor, 60)
            .click(self, @selector(disconnect));
    }
}

-(void)loadVNCWithURL:(NSURL *)url {
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

-(void)disconnect {
    [self.navigationController popViewControllerAnimated:YES];
}

@end
