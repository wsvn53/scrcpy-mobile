//
//  ScrcpySwitch.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/14.
//

#import "ScrcpySwitch.h"
#import "KFKeychain.h"

@implementation ScrcpySwitch

-(void)setOptionKey:(NSString *)optionKey {
    _optionKey = optionKey;
    NSNumber *optionValue = [KFKeychain loadObjectForKey:optionKey];
    if (optionValue) {
        self.on = [optionValue boolValue];
    }
}

-(void)updateOptionValue {
    [KFKeychain saveObject:@(self.on) forKey:self.optionKey];
}

@end
