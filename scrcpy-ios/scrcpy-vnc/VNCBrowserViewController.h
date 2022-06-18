//
//  VNCBrowserViewController.h
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/15.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VNCBrowserViewController : UIViewController

@property (nonatomic, copy)  NSString   *vncURL;
@property (nonatomic, assign)   BOOL    showsFullscreen;

@end

NS_ASSUME_NONNULL_END
