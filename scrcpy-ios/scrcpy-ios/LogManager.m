//
//  LogManager.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/7/19.
//

#import "LogManager.h"

#define kRecentLogsLimit   512*1024

@interface LogManager ()

@property (nonatomic, copy) NSString    *logPath;

@end

@implementation LogManager

+(instancetype)sharedManager {
    static LogManager *mananger = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mananger = [[LogManager alloc] init];
    });
    return mananger;
}

-(NSString *)logPath {
    return _logPath ?: ({
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM"];
        NSString *dateString = [formatter stringFromDate:[NSDate date]];
        NSArray *allPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [allPaths objectAtIndex:0];
        NSString *logName = [NSString stringWithFormat:@"scrcpy@%@", dateString];
        _logPath = [documentsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.log", logName]];
    });
}

-(void)startHandleLog {
    freopen([self.logPath cStringUsingEncoding:NSASCIIStringEncoding],"a+",stderr);
    freopen([self.logPath cStringUsingEncoding:NSASCIIStringEncoding],"a+",stdout);
}

-(NSString *)recentLogs {
    NSFileHandle *logHandle = [NSFileHandle fileHandleForReadingAtPath:self.logPath];
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:self.logPath error:nil];
    NSInteger fileSize = [attrs[NSFileSize] integerValue];
    NSLog(@"LogPath: %@, Size: %@", self.logPath, @(fileSize));
    if (fileSize > kRecentLogsLimit) {
        [logHandle seekToFileOffset:fileSize-kRecentLogsLimit];
    }
    NSData *logData = [logHandle readDataOfLength:kRecentLogsLimit];
    return [[NSString alloc] initWithData:logData encoding:NSUTF8StringEncoding];
}

@end
