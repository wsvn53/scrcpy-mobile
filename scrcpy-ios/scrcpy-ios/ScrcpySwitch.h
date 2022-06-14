//
//  ScrcpySwitch.h
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/14.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpySwitch : UISwitch

@property (nonatomic, copy)     NSString    *optionKey;

-(void)updateOptionValue;

@end

NS_ASSUME_NONNULL_END
