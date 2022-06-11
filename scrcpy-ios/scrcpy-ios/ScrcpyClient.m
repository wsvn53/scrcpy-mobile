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
#import <UIKit/UIKit.h>
#import <libavutil/frame.h>
#import <video_buffer.h>

#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>

@interface ScrcpyClient ()
// Connecting infomations
@property (nonatomic, copy) NSString    *connectedSerial;

// Scrcpy status
@property (nonatomic, assign)   enum ScrcpyStatus   status;

// Underlying ADB status change callback
@property (nonatomic, copy)     void (^adbStatusUpdated)(NSString *serial, NSString *status);

// Underlying Scrcpy status change callback
@property (nonatomic, copy)     void (^scrcpyStatusUpdated)(enum ScrcpyStatus status);

@end

CFRunLoopRunResult CFRunLoopRunInMode_fix(CFRunLoopMode mode, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {
    // Upper runloop duration to reduce CPU usage
    return CFRunLoopRunInMode(mode, 0.0025, returnAfterSourceHandled);
}

void adb_connect_status_updated(const char *serial, const char *status) {
    NSString *adbSerial = [NSString stringWithUTF8String:serial];
    NSString *adbStatus = [NSString stringWithUTF8String:status];
    if (ScrcpySharedClient.adbStatusUpdated)
        ScrcpySharedClient.adbStatusUpdated(adbSerial, adbStatus);
}

void ScrcpyUpdateStatus(enum ScrcpyStatus status) {
   if (ScrcpySharedClient.scrcpyStatusUpdated)
       ScrcpySharedClient.scrcpyStatusUpdated(status);
}

float screen_scale(void) {
    if ([UIScreen.mainScreen respondsToSelector:@selector(nativeScale)]) {
        return UIScreen.mainScreen.nativeScale;
    }
    return UIScreen.mainScreen.scale;
}

bool ScrcpyEnableHardwareDecoding(void) {
    return true;
}

void RenderPixelBufferFrame(CVPixelBufferRef pixelBuffer) {
    if (pixelBuffer == NULL) { return; }
    
    CMSampleTimingInfo timing = {kCMTimeInvalid, kCMTimeInvalid, kCMTimeInvalid};
    CMVideoFormatDescriptionRef videoInfo = NULL;
    OSStatus result = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &videoInfo);
    
    CMSampleBufferRef sampleBuffer = NULL;
    result = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,pixelBuffer, true, NULL, NULL, videoInfo, &timing, &sampleBuffer);
    
    CFRelease(pixelBuffer);
    CFRelease(videoInfo);
    
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    
    static AVSampleBufferDisplayLayer *displayLayer = nil;
    if (displayLayer == nil || displayLayer.superlayer == nil) {
        displayLayer = [AVSampleBufferDisplayLayer layer];
        displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        
        UIWindow *keyWindow = [UIApplication.sharedApplication.windows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UIWindow *window, id bindings) {
            return window.isKeyWindow;
        }]].firstObject;
        
        if ([NSStringFromClass(keyWindow.class) hasPrefix:@"SDL"] == NO)
            return;
        
        displayLayer.frame = keyWindow.rootViewController.view.bounds;
        [keyWindow.rootViewController.view.layer addSublayer:displayLayer];
        keyWindow.rootViewController.view.backgroundColor = UIColor.blackColor;
        // sometimes failed to set background color, so we append to next runloop
        displayLayer.backgroundColor = UIColor.blackColor.CGColor;
        NSLog(@"[INFO] Using Hardware Decoding.");
    }
    
    // After become forground from background, may render fail
    if (displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        [displayLayer flush];
    }
    
    // render sampleBuffer now
    [displayLayer enqueueSampleBuffer:sampleBuffer];
}

void ScrcpyHandleFrame(AVFrame *frame) {
    if (ScrcpyEnableHardwareDecoding() == false) {
        return;
    }
    
    CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)frame->data[3];
    RenderPixelBufferFrame(pixelBuffer);
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
    
    // Add notifcation to responds background mode changed
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(sendRotateCommand)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];
}

-(void)sendRotateCommand {
    NSLog(@"-> Send Command Trigger Video Restart");
    
    SDL_Keysym keySym;
    keySym.scancode = SDL_SCANCODE_END;
    keySym.sym = SDLK_END;
    keySym.mod = 0;
    keySym.unused = 1;
    
    SDL_KeyboardEvent keyEvent;
    keyEvent.type = SDL_KEYUP;
    keyEvent.state = SDL_PRESSED;
    keyEvent.repeat = '\0';
    keyEvent.keysym = keySym;
    
    SDL_Event event;
    event.type = keyEvent.type;
    event.key = keyEvent;
    
    SDL_PushEvent(&event);
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
    NSMutableDictionary *statusFlags = [NSMutableDictionary dictionary];
    self.adbStatusUpdated = ^(NSString *serial, NSString *status) {
        if ([@[@"device", @"unauthorized"] containsObject:status] &&
            [statusFlags[status] boolValue]) {
            NSLog(@"Ignore this status update, because already changed before");
            return;
        }
        statusFlags[status] = @YES;
        [_self onADBStatusChanged:serial status:status options:scrcpyOptions];
    };
    adbPort = adbPort.length == 0 ? @"5555" : adbPort;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self adbConnect:adbHost port:adbPort];
    });
}

-(void)onADBStatusChanged:(NSString *)serial
                   status:(NSString *)status
                  options:(NSArray *)scrcpyOptions {
    NSLog(@"ADB Status Updated: %@ - %@", serial, status);
    // Prevent multipile called start
    if ([status isEqualToString:@"device"] &&
        self.status != ScrcpyStatusConnected) {
        if (self.onADBConnected != nil) self.onADBConnected(serial);
        self.connectedSerial = serial;
        [self performSelectorOnMainThread:@selector(startWithOptions:) withObject:scrcpyOptions waitUntilDone:NO];
    } else if ([status isEqualToString:@"unauthorized"]) {
        if (self.onADBUnauthorized != nil) self.onADBUnauthorized(serial);
    }
}

-(void)startWithOptions:(NSArray *)scrcpyOptions {
    __weak typeof(self) _self = self;
    self.scrcpyStatusUpdated = ^(enum ScrcpyStatus status) {
        if (status == ScrcpyStatusConnected && _self.onScrcpyConnected) {
            _self.onScrcpyConnected(_self.connectedSerial);
            return;
        }
        
        if (status == ScrcpyStatusDisconnected && _self.onScrcpyDisconnected) {
            _self.onScrcpyDisconnected(_self.connectedSerial);
            return;
        }
        
        if (status == ScrcpyStatusConnectingFailed && _self.onScrcpyConnectFailed) {
            _self.onScrcpyConnectFailed(_self.connectedSerial);
            return;
        }
    };
    
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
