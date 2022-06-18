//
//  HTTPFileResponse+Extend.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/16.
//

#import "HTTPFileResponse+Extend.h"

@implementation HTTPFileResponse (Extend)

-(NSDictionary *)httpHeaders {
    if ([self.filePath hasSuffix:@".svg"]) {
        return @{
            @"Content-Type": @"image/svg+xml"
        };
    }
    
    if ([self.filePath hasSuffix:@".js"]) {
        return @{
            @"Content-Type": @"application/javascript"
        };
    }
    
    return @{};
}

@end
