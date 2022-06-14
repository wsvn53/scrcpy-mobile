//
//  ScrcpyTextField.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/12.
//

#import "ScrcpyTextField.h"
#import "KFKeychain.h"

@implementation ScrcpyTextField

-(void)setOptionKey:(NSString *)optionKey {
    _optionKey = optionKey;
    self.text = [KFKeychain loadObjectForKey:optionKey];
}

-(void)updateOptionValue {
    [KFKeychain saveObject:self.text forKey:self.optionKey];
}

-(CGRect)textRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0, 6, 0, 6));
}

-(CGRect)placeholderRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0, 6, 0, 6));
}

-(CGRect)editingRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0, 6, 0, 6));
}

@end
