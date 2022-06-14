//
//  ScrcpyTextField.h
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/12.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyTextField : UITextField

@property (nonatomic, copy)     NSString *optionKey;

-(void)updateOptionValue;

@end

NS_ASSUME_NONNULL_END
