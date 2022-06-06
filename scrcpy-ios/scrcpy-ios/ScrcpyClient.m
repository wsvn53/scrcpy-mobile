//
//  ScrcpyClient.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/2.
//

#import "ScrcpyClient.h"
#import "scrcpy-porting.h"
#import "adb_public.h"
#import <SDL2/SDL_events.h>
#import <SDL2/SDL_system.h>

@interface ScrcpyClient ()
// Connecting infomations
@property (nonatomic, copy) NSString    *connectedSerial;

// Scrcpy status
@property (nonatomic, assign)   enum ScrcpyStatus   status;

// Underlying ADB status change callback
@property (nonatomic, copy)     void (^adbStatusUpdated)(NSString *serial, NSString *status);

@end

CFRunLoopRunResult CFRunLoopRunInMode_fix(CFRunLoopMode mode, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {
    // Upper runloop duration to reduce CPU usage
    return CFRunLoopRunInMode(mode, 0.0025, returnAfterSourceHandled);
}

void adb_connect_status_updated(const char *serial, const char *status) {
    NSString *adbSerial = [NSString stringWithUTF8String:serial];
    NSString *adbStatus = [NSString stringWithUTF8String:status];
    if (ScrcpySharedClient.adbStatusUpdated) ScrcpySharedClient.adbStatusUpdated(adbSerial, adbStatus);
}

@implementation ScrcpyClient

+(instancetype)sharedClient
{
    static ScrcpyClient *client = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [[ScrcpyClient alloc] init];
        [client setup];
    });
    return client;
}

-(void)setup {
    // ADB Settings
    self.adbDaemonPort = 15037;
    
    // Set ADB Home
    NSArray <NSString *> *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    self.adbHomePath = documentPaths.firstObject;
}

#pragma mark - Scrcpy Lifetime

-(void)startWith:(NSString *)adbHost
         adbPort:(NSString *)adbPort
         options:(NSArray *)scrcpyOptions
{
    if (self.connectedSerial.length != 0 ||
        self.status == ScrcpyStatusConnected) {
        [self stopScrcpy];
    }
    
    // Connect ADB First
    __weak typeof(self) _self = self;
    self.adbStatusUpdated = ^(NSString *serial, NSString *status) {
        [_self onADBStatusChanged:serial status:status options:scrcpyOptions];
    };
    adbPort = adbPort.length == 0 ? @"5555" : adbPort;
    [self adbConnect:adbHost port:adbPort];
}

-(void)onADBStatusChanged:(NSString *)serial
                   status:(NSString *)status
                  options:(NSArray *)scrcpyOptions {
    NSLog(@"ADB Status Updated: %@ - %@", serial, status);
    // Prevent multipile called start
    if ([status isEqualToString:@"device"] && self.status != ScrcpyStatusConnected) {
        [self performSelectorOnMainThread:@selector(startWithOptions:) withObject:scrcpyOptions waitUntilDone:NO];
    } else if ([status isEqualToString:@"unauthorized"] && self.onADBUnauthorized) {
        self.onADBUnauthorized(serial);
    }
}

-(void)startWithOptions:(NSArray *)scrcpyOptions {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, NO);

    // Because after SDL proxied didFinishLauch, PumpEvent will set to FASLE
    // So we need to set to TRUE in order to handle UI events
    SDL_iPhoneSetEventPump(SDL_TRUE);
    
    // Flush all events include the not proccessed SERVER_DISCONNECT events
    SDL_FlushEvents(0, 0xFFFF);
    
    // Setup arguments
    int idx = 0;
    const char *args[20];
    args[idx] = "scrcpy";
    while ((++idx) && idx <= scrcpyOptions.count) {
        args[idx] = [scrcpyOptions[idx-1] UTF8String];
    }

    ScrcpyUpdateStatus(ScrcpyStatusConnecting);
    scrcpy_main((int)scrcpyOptions.count+1, (char **)args);
    ScrcpyUpdateStatus(ScrcpyStatusDisconnected);
}

-(void)stopScrcpy {
    // Call SQL_Quit to send Quit Event
    SDL_Event event;
    event.type = SDL_QUIT;
    SDL_PushEvent(&event);
    
    // Disconnect ADB core
    [self adbDisconnect:nil port:nil];
    
    // Wait for scrcpy exited
    while (self.status != ScrcpyStatusDisconnected) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, NO);
    }
}

#pragma mark - ADB Lifetime

-(void)enableADBVerbose {
    adb_enable_trace();
}

-(void)setAdbDaemonPort:(NSInteger)adbDaemonPort {
    _adbDaemonPort = adbDaemonPort;
    adb_set_server_port([NSString stringWithFormat:@"%ld", adbDaemonPort].UTF8String);
}

-(void)setAdbHomePath:(NSString *)adbHomePath {
    _adbHomePath = adbHomePath;
    adb_set_home(adbHomePath.UTF8String);
}

-(void)adbConnect:(NSString *)adbHost port:(NSString *)adbPort {
    adbPort = adbPort.length == 0 ? @"5555" : adbPort;
    NSString *serial = [NSString stringWithFormat:@"%@:%@", adbHost, adbPort];
    
    NSString *devices = nil;
    [self adbExecute:@[ @"devices" ] message:&devices];
    NSArray *deviceLines = [devices componentsSeparatedByString:@"\n"];
    for (NSString *device in deviceLines) {
        if ([device containsString:serial] && [devices containsString:@"unauthorized"]) {
            NSLog(@"adb device unauthorized %@", serial);
            if (self.adbStatusUpdated) self.adbStatusUpdated(serial, @"unauthorized");
            return;
        }

        if ([device containsString:serial] && [devices containsString:@"device"]) {
            NSLog(@"adb device already connected %@", serial);
            if (self.adbStatusUpdated) self.adbStatusUpdated(serial, @"device");
            return;
        }
    }
    
    // Disconnect all before connect
    [self adbDisconnect:nil port:nil];
    
    NSString *message = nil;
    NSInteger code = [self adbExecute:@[@"connect", serial] message:&message];
    NSLog(@"adb connnect code: %ld, message: %@", code, message);
    
    [self adbExecute:@[@"get-serialno"] message:&message];
    NSLog(@"adb get-serialno: %@", message);
}

-(void)adbDisconnect:(NSString *)adbHost port:(NSString *)adbPort {
    NSString *message = nil;
    if (adbHost.length == 0) {
        [self adbExecute:@[ @"disconnect" ] message:&message];
        if (message.length > 0) {
            NSLog(@"adb disconnect: %@", message);
        }
        return;
    }
    
    adbPort = adbPort.length == 0 ? @"5555" : adbPort;
    
    NSString *target = [NSString stringWithFormat:@"%@:%@", adbHost, adbPort];
    [self adbExecute:@[ @"disconnect", target ] message:&message];
    if (message.length > 0) {
        NSLog(@"adb disconnect: %@", message);
    }
}

-(BOOL)adbExecute:(NSArray <NSString *> *)commands message:(NSString **)message {
    NSInteger code = [self adbExecuteUnderlying:commands message:message];
    return code == 0;
}

-(NSInteger)adbExecuteUnderlying:(NSArray<NSString *> *)commands message:(NSString **)message {
    int argc = (int)commands.count;
    char *argv[argc];
    for (int i = 0; i < argc; i++) {
        argv[i] = strdup(commands[i].UTF8String);
    }
    char *output_message;
    int code = adb_commandline_porting(argc, (const char **)argv, &output_message);
    if (message != nil)
        *message = output_message == NULL ? nil : [NSString stringWithUTF8String:output_message];
    return (NSInteger)code;
}

@end
