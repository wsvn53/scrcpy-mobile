//
//  LogManager.h
//  scrcpy-ios
//
//  Created by Ethan on 2022/7/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LogManager : NSObject

+(instancetype)sharedManager;

-(void)startHandleLog;

-(NSString *)recentLogs;

@end

NS_ASSUME_NONNULL_END
