//
//  SDL_uikitviewcontroller+Extend.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/11.
//

#import "SDL_uikitviewcontroller+Extend.h"
#import <AVFoundation/AVFoundation.h>

@implementation SDL_uikitviewcontroller (Extend)

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self.view.layer.sublayers enumerateObjectsUsingBlock:^(CALayer *layer, NSUInteger idx, BOOL *stop) {
        layer.frame = self.view.bounds;
    }];
}

@end
