//
//  ScrcpyClient.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/2.
//

#import "ScrcpyClient.h"
#import "scrcpy-porting.h"
#import "adb_public.h"
#import <UIKit/UIKit.h>
#import <libavutil/frame.h>

#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>

#import "SDLUIKitDelegate+Extend.h"

@interface ScrcpyClient ()
// Connecting infomations
@property (nonatomic, copy) NSString    *connectedSerial;

// Scrcpy status
@property (nonatomic, assign)   enum ScrcpyStatus   status;

// Underlying ADB status change callback
@property (nonatomic, copy)     void (^adbStatusUpdated)(NSString *serial, NSString *status);

// Underlying Scrcpy status change callback
@property (nonatomic, copy)     void (^scrcpyStatusUpdated)(enum ScrcpyStatus status);

// ADB Start Queue
@property (nonatomic, strong)   NSOperationQueue    *adbStartQueue;

@end

CFRunLoopRunResult CFRunLoopRunInMode_fix(CFRunLoopMode mode, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {
    // Upper runloop duration to reduce CPU usage
    // Audio Thread using seconds == 0.100000001f, so dynamic change
    // the runloop duration here can reduce CPU cost
    seconds = seconds >= 0.1f ? seconds : ({
        ScrcpySharedClient.enablePowerSavingMode ? 0.002f : 0.0001f;
    });
    return CFRunLoopRunInMode(mode, seconds, returnAfterSourceHandled);
}

void adb_connect_status_updated(const char *serial, const char *status) {
    NSString *adbSerial = [NSString stringWithUTF8String:serial];
    NSString *adbStatus = [NSString stringWithUTF8String:status];
    if (ScrcpySharedClient.adbStatusUpdated)
        ScrcpySharedClient.adbStatusUpdated(adbSerial, adbStatus);
}

void ScrcpyUpdateStatus(enum ScrcpyStatus status) {
    ScrcpySharedClient.status = status;
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
#if TARGET_IPHONE_SIMULATOR
    return false;
#else
    return true;
#endif
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
        [displayLayer removeFromSuperlayer];
        displayLayer = [AVSampleBufferDisplayLayer layer];
        displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        
        UIWindow *sdlWindow = [UIApplication.sharedApplication.windows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UIWindow *window, id bindings) {
            return [NSStringFromClass([window class]) containsString:@"SDL_"];
        }]].firstObject;
        
        // Skip when no SDL window found
        if (sdlWindow == nil) return;
        
        displayLayer.frame = sdlWindow.rootViewController.view.bounds;
        [sdlWindow.rootViewController.view.layer addSublayer:displayLayer];
        sdlWindow.rootViewController.view.backgroundColor = UIColor.blackColor;
        // sometimes failed to set background color, so we append to next runloop
        displayLayer.backgroundColor = UIColor.blackColor.CGColor;
        NSLog(@"[INFO] Using hardware decoding.");
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
    });
    return client;
}

+(void)load {
    [ScrcpySharedClient setup];
}

-(void)setup {
    // ADB Settings
    self.adbDaemonPort = 15037;
    self.adbStartQueue = [[NSOperationQueue alloc] init];
    self.adbStartQueue.maxConcurrentOperationCount = 1;
    
    // Set ADB Home
    NSArray <NSString *> *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    self.adbHomePath = documentPaths.firstObject;
    
    // Add notification to responds background mode changed
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(onApplicationEnterForeground)
                                               name:UIApplicationDidBecomeActiveNotification
                                             object:nil];
    
    // Add notification to handle URL open
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleScrcpyURLScheme:)
                                               name:ScrcpyConnectWithSchemeNotification
                                             object:nil];
}

#pragma mark - Events

-(void)onApplicationEnterForeground {
    [self checkStartScheme];
    [self onStartOrResume];
}

-(void)onStartOrResume {
    if (self.status == ScrcpyStatusConnected) {
        NSLog(@"-> Send command to trigger video restart I frame");
        [self sendKeycodeEvent:SDL_SCANCODE_END keycode:SDLK_END keymod:0];
        
        NSLog(@"-> Syncing clipboard");
        SDL_Event clip_event;
        clip_event.type = SDL_CLIPBOARDUPDATE;

        BOOL posted = (SDL_PushEvent(&clip_event) > 0);
        NSLog(@"CLIPBOARD EVENT: Post %@", posted? @"Success" : @"Failed");
    }
}

-(void)handleScrcpyURLScheme:(NSNotification *)notification {
    NSURL *openingURL = notification.userInfo[ScrcpyConnectWithSchemeURLKey];
    NSLog(@"-> URL Scheme: %@", openingURL);
    if (openingURL == nil || [openingURL.scheme isEqualToString:@"scrcpy2"] == NO) {
        NSLog(@"-> Invalid URL Scheme: URL is not supported");
        return;
    }
    self.pendingScheme = openingURL;
}

#pragma mark - Scrcpy Lifetime

-(void)checkStartScheme {
    if (self.pendingScheme == nil) {
        return;
    }
    
    if ([UIApplication.sharedApplication.windows filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF.isKeyWindow = %@", @YES]].count == 0) {
        return;
    }
    
    NSURL *pendingScheme = self.pendingScheme;
    // Mark here to avoid both forground notification and viewAppear trigger twice
    self.pendingScheme = nil;
    
    NSString *adbHost = pendingScheme.host;
    NSString *adbPort = pendingScheme.port.stringValue ? : @"5555";
    
    if (adbHost.length == 0) {
        NSLog(@"[ERROR] No adb host found in scheme");
        return;
    }
    
    __block NSArray *scrcpyOptions = self.defaultScrcpyOptions;
    NSURLComponents *urlComps = [NSURLComponents componentsWithURL:pendingScheme resolvingAgainstBaseURL:YES];
    [urlComps.queryItems enumerateObjectsUsingBlock:^(NSURLQueryItem *query, NSUInteger idx, BOOL *stop) {
        // if value == true, set value to "" in order to match commandline style scrcpy option like --turn-screen-off
        NSString *value = [query.value isEqualToString:@"true"] ? @"" : query.value;
        scrcpyOptions = [self setScrcpyOption:scrcpyOptions name:query.name value:value];
        
        if ([query.name isEqualToString:@"show-nav-buttons"]) {
            self.shouldAlwaysShowNavButtons = [query.value boolValue];
        }
        
        if ([query.name isEqualToString:@"power-saving"]) {
            self.enablePowerSavingMode = [query.value boolValue];
        }
    }];
    
    NSLog(@"-> Scrcpy Options: %@", scrcpyOptions);
    [self startWith:adbHost adbPort:adbPort options:scrcpyOptions];
}

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
    
    // Connecting callback
    if (self.onADBConnecting) {
        NSString *serial = [NSString stringWithFormat:@"%@:%@", adbHost, adbPort];
        self.onADBConnecting(serial);
    }
    
    [self.adbStartQueue addOperationWithBlock:^{
        [self adbConnect:adbHost port:adbPort];
    }];
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
    
    // Power saving options
    if (self.enablePowerSavingMode) {
        NSLog(@"Power saving mode enabled, --max-fps set to 30hz");
        scrcpyOptions = [self setScrcpyOption:scrcpyOptions name:@"max-fps" value:@"30"];
    }
    
    self.scrcpyStatusUpdated = ^(enum ScrcpyStatus status) {
        if (status == ScrcpyStatusConnected && _self.onScrcpyConnected) {
            _self.onScrcpyConnected(_self.connectedSerial);
            [_self onStartOrResume];
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

-(void)startADBServer {
    [self.adbStartQueue addOperationWithBlock:^{
        NSString *message = @"";
        BOOL success = [self adbExecute:@[@"start-server"] message:&message];
        NSLog(@"Start ADB Server: %@", success?@"YES":@"NO");
        if (message.length > 0) printf("-> %s\n", message.UTF8String);
    }];
}

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
    if ([message containsString:@"failed"] && self.onADBConnectFailed) {
        self.onADBConnectFailed(serial, message);
    }
    
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

#pragma mark - Scrcpy Options

-(NSArray *)defaultScrcpyOptions {
    return @[ @"--verbosity=debug", @"--fullscreen",
              /** @"--video-codec=h265", **/ @"--video-bit-rate=4M",
              @"--audio-bit-rate=128K", @"--audio-buffer=60", @"--no-audio",
              @"--max-fps=60", @"--print-fps" ];
}

-(NSArray *)availableOptions {
    return @[ @"max-size", @"video-bit-rate", @"audio-bit-rate", @"audio-buffer",
              @"audio-codec", @"no-audio", @"disable-screensaver", @"video-buffer",
              @"force-adb-forward", @"max-fps", @"power-off-on-close", @"turn-screen-off",
              @"show-touches", @"stay-awake", @"new-display", @"start-app", ];
}

-(NSArray *)setScrcpyOption:(NSArray *)options name:(NSString *)name value:(NSString *)value {
    // Enable audio
    if ([name isEqualToString:@"enable-audio"] && [options containsObject:@"--no-audio"]) {
        // Remove --no-audio in default options
        NSMutableArray *newOptions = [NSMutableArray arrayWithArray:options];
        [newOptions removeObject:@"--no-audio"];
        return newOptions;
    }
    
    // Check available options
    if ([self.availableOptions containsObject:name] == NO) {
        NSLog(@"-> Not supported: %@", name);
        return options;
    }
    
    // Remove existed defaults options
    NSArray *existedOptions = [options filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *option, id bindings) {
        return [option containsString:name];
    }]];
    
    NSMutableArray *scrcpyOptions = [NSMutableArray arrayWithArray:options];
    [scrcpyOptions removeObjectsInArray:existedOptions];
    
    // Add new option
    NSString *newOption = [NSString stringWithFormat:@"--%@", name];
    if (value.length > 0) {
        newOption = [newOption stringByAppendingFormat:@"=%@", value];
    }
    [scrcpyOptions addObject:newOption];
    
    return scrcpyOptions;
}

#pragma mark - Send Keys

-(void)sendKeycodeEvent:(SDL_Scancode)scancode keycode:(SDL_Keycode)keycode keymod:(SDL_Keymod)keymod {
    SDL_Keysym keySym;
    keySym.scancode = scancode;
    keySym.sym = keycode;
    keySym.mod = keymod;
    keySym.unused = 1;
    
    {
        SDL_KeyboardEvent keyEvent;
        keyEvent.type = SDL_KEYDOWN;
        keyEvent.state = SDL_PRESSED;
        keyEvent.repeat = '\0';
        keyEvent.keysym = keySym;
        
        SDL_Event event;
        event.type = keyEvent.type;
        event.key = keyEvent;
        
        SDL_PushEvent(&event);
    }
    
    {
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
}

-(void)sendHomeButton {
    NSLog(@"-> Send Home Button");
    [self sendKeycodeEvent:SDL_SCANCODE_H keycode:SDLK_h keymod:KMOD_CTRL];
}

-(void)sendBackButton {
    NSLog(@"-> Send Back Button");
    [self sendKeycodeEvent:SDL_SCANCODE_B keycode:SDLK_b keymod:KMOD_CTRL];
}

-(void)sendSwitchAppButton {
    NSLog(@"-> Send Switch App Button");
    [self sendKeycodeEvent:SDL_SCANCODE_S keycode:SDLK_s keymod:KMOD_CTRL];
}

@end
