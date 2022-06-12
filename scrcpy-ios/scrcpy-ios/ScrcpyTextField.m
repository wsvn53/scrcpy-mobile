//
//  ScrcpyTextField.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/12.
//

#import "ScrcpyTextField.h"

@implementation ScrcpyTextField

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
