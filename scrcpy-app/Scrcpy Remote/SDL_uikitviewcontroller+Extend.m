//
//  SDL_uikitviewcontroller+Extend.m
//  Scrcpy Remote
//
//  Created by Ethan on 1/4/25.
//

#import "SDL_uikitviewcontroller+Extend.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <SDL3/SDL.h>
#import <SDL3/SDL_events.h>
#import <SDL3/SDL_system.h>
#import "ScrcpyClientWrapper.h"
#import "ADBClient.h"
#import "ScrcpyADBClient.h"
#import "ScrcpyRuntime.h"
#import "ScrcpyMenuView.h"
#import "ScrcpyInputMaskView.h"
#import "ScrcpyCommon.h"
#import "Scrcpy_Remote-Swift.h"
#import "ScrcpyConstants.h"

// External notification name from ScrcpyRuntime
extern NSString * const ScrcpyRemoteOrientationChangedNotification;

// Track last known window size for Stage Manager detection
static CGSize g_lastKnownViewSize = {0, 0};

@interface SDL_uikitviewcontroller () <ScrcpyMenuViewDelegate>
// NOTE: homeIndicatorHidden is SDL3's own ivar; we drive it through
// SDL_HINT_IOS_HIDE_HOME_INDICATOR rather than redeclaring it here.
@end

@implementation SDL_uikitviewcontroller (Extend)

// Key for menuView associated object
static char menuViewKey;
static char inputMaskViewKey;
static char lockedOrientationMaskKey;
static char orientationLockEnabledKey;

#pragma mark - Method Swizzling for Orientation Control

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];

        // Swizzle supportedInterfaceOrientations
        SEL originalSelector = @selector(supportedInterfaceOrientations);
        SEL swizzledSelector = @selector(scrcpy_supportedInterfaceOrientations);

        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

        // If the original method doesn't exist, add it first
        BOOL didAddMethod = class_addMethod(class,
                                            originalSelector,
                                            method_getImplementation(swizzledMethod),
                                            method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            class_replaceMethod(class,
                               swizzledSelector,
                               method_getImplementation(originalMethod),
                               method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }

        NSLog(@"📱 [SDL_uikitviewcontroller] Method swizzling completed for supportedInterfaceOrientations");
    });
}

- (UIInterfaceOrientationMask)scrcpy_supportedInterfaceOrientations {
    // If orientation lock is enabled, return only the locked orientation
    if ([self isOrientationLockEnabled]) {
        UIInterfaceOrientationMask lockedMask = [self lockedOrientationMask];
        NSLog(@"📱 [SDL_uikitviewcontroller] Returning locked orientation mask: %lu", (unsigned long)lockedMask);
        return lockedMask;
    }

    // Otherwise, call original implementation (which allows all orientations)
    return [self scrcpy_supportedInterfaceOrientations];
}

// Getter for menuView
- (ScrcpyMenuView *)menuView {
    return objc_getAssociatedObject(self, &menuViewKey);
}

// Setter for menuView
- (void)setMenuView:(ScrcpyMenuView *)menuView {
    objc_setAssociatedObject(self, &menuViewKey, menuView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Getter for inputMaskView
- (ScrcpyInputMaskView *)inputMaskView {
    return objc_getAssociatedObject(self, &inputMaskViewKey);
}

// Setter for inputMaskView
- (void)setInputMaskView:(ScrcpyInputMaskView *)inputMaskView {
    objc_setAssociatedObject(self, &inputMaskViewKey, inputMaskView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Getter for lockedOrientationMask
- (UIInterfaceOrientationMask)lockedOrientationMask {
    NSNumber *value = objc_getAssociatedObject(self, &lockedOrientationMaskKey);
    return value ? [value unsignedIntegerValue] : UIInterfaceOrientationMaskAll;
}

// Setter for lockedOrientationMask
- (void)setLockedOrientationMask:(UIInterfaceOrientationMask)mask {
    objc_setAssociatedObject(self, &lockedOrientationMaskKey, @(mask), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Getter for orientationLockEnabled
- (BOOL)isOrientationLockEnabled {
    NSNumber *value = objc_getAssociatedObject(self, &orientationLockEnabledKey);
    return value ? [value boolValue] : NO;
}

// Setter for orientationLockEnabled
- (void)setOrientationLockEnabled:(BOOL)enabled {
    objc_setAssociatedObject(self, &orientationLockEnabledKey, @(enabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];

    // Update video layer frame
    for (CALayer *layer in self.view.layer.sublayers) {
        if ([layer isKindOfClass:AVSampleBufferDisplayLayer.class]) {
            layer.frame = self.view.bounds;
        }
    }

    // Update menu view layout if it exists
    if (self.menuView) {
        [self.menuView updateLayout];
    }

    // Stage Manager fix: Notify SDL of window size changes
    // This is critical for correct touch coordinate mapping in floating windows
    [self notifySDLWindowSizeChangeIfNeeded];
}

#pragma mark - Stage Manager Window Size Fix

- (void)notifySDLWindowSizeChangeIfNeeded {
    [self notifySDLWindowSizeChangeForced:NO];
}

- (void)notifySDLWindowSizeChangeForced:(BOOL)force {
    CGSize currentViewSize = self.view.bounds.size;

    // Skip invalid sizes
    if (currentViewSize.width <= 0 || currentViewSize.height <= 0) {
        return;
    }

    // Window coordinates (points), NOT pixels.
    //
    // This comparison must be made in the same unit SDL_GetWindowSize() below
    // reports, and SDL3 documents that as "the client area's size in window
    // coordinates" — points on a Retina display; SDL_GetWindowSizeInPixels()
    // is the pixel variant. SDL2 returned pixels here on iOS, which is why the
    // original SDL2-era code multiplied by nativeScale; carrying that multiply
    // across the SDL3 migration compared points against pixels, so the sizes
    // never matched, the mismatch branch fired on every single layout pass,
    // and each pass pushed a resize event carrying a pixel-sized geometry.
    //
    // Points are also the right unit to *push*: upstream's whole geometry and
    // input chain works in them (sc_sdl_get_window_size() -> SDL_GetWindowSize(),
    // and SDL mouse/touch events are documented "relative to window"). Fixing
    // this by comparing in pixels instead would stop the loop but hand upstream
    // a pixel-sized window, moving the error rather than removing it.
    int newWidth = (int)currentViewSize.width;
    int newHeight = (int)currentViewSize.height;

    // Get SDL window to compare sizes
    SDL_Window *sdlWindow = SDL_GetKeyboardFocus();
    if (!sdlWindow) {
        sdlWindow = SDL_GetMouseFocus();
    }

    int sdlWidth = 0, sdlHeight = 0;
    if (sdlWindow) {
        SDL_GetWindowSize(sdlWindow, &sdlWidth, &sdlHeight);
    }

    // Skip only when nothing has changed: view size matches cache AND SDL's
    // own cached size already matches the actual view size. We must re-check
    // SDL even if view bounds equal the cached value, because Slide Over
    // hide/restore can leave SDL's coordinate-mapping rect stale without ever
    // changing self.view.bounds.
    BOOL sdlMatches = (sdlWindow && sdlWidth == newWidth && sdlHeight == newHeight);
    if (!force && CGSizeEqualToSize(currentViewSize, g_lastKnownViewSize) && sdlMatches) {
        return;
    }

    if (sdlWindow) {
        if (sdlWidth != newWidth || sdlHeight != newHeight) {
            NSLog(@"📐 [StageManager] Window size mismatch detected - SDL: %dx%d, Actual: %dx%d",
                  sdlWidth, sdlHeight, newWidth, newHeight);

            // Push SDL window resize event to trigger scrcpy's coordinate recalculation.
            // This makes sc_screen_update_content_rect() recalculate the touch mapping rect.
            // SDL3 flattened window events: the type IS the specific window event
            // (no more separate event.window.event sub-discriminator).
            SDL_Event event;
            SDL_memset(&event, 0, sizeof(event));
            event.type = SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED;
            event.window.data1 = newWidth;
            event.window.data2 = newHeight;
            event.window.windowID = SDL_GetWindowID(sdlWindow);
            SDL_PushEvent(&event);

            // Also push RESIZED. Upstream treats the two differently:
            // PIXEL_SIZE_CHANGED ignores data1/data2 and just re-renders
            // (sc_screen_render re-queries the sizes itself), while RESIZED
            // reads the payload — under --flex-display it forwards it to
            // sc_screen_request_resize_display(). That consumer wants window
            // coordinates, which is what we now send.
            event.type = SDL_EVENT_WINDOW_RESIZED;
            SDL_PushEvent(&event);

            NSLog(@"📐 [StageManager] Pushed SDL window resize events: %dx%d", newWidth, newHeight);
        }
    }

    g_lastKnownViewSize = currentViewSize;
}

// MARK: - Home indicator + edge gesture handling
//
// IMPORTANT: do NOT override prefersHomeIndicatorAutoHidden /
// preferredScreenEdgesDeferringSystemGestures here. SDL3's own
// SDL_uikitviewcontroller already implements both, driven by its
// private `homeIndicatorHidden` ivar:
//
//   homeIndicatorHidden == 0  -> indicator shown,  edges = None
//   homeIndicatorHidden == 1  -> indicator hidden, edges = None
//   homeIndicatorHidden == 2  -> indicator hidden, edges = UIRectEdgeAll
//   homeIndicatorHidden <  0  -> indicator default, edges = All if fullscreen
//
// A category that re-implements the same selectors collides with SDL's
// implementation (undefined which one the runtime keeps) AND can't see
// SDL's ivar value anyway. In SDL2 a fullscreen window defaulted to
// deferring all screen edges; in SDL3 the ivar defaults to 0, so the
// edge-defer path returns None and a single bottom swipe drops straight
// to the iOS home screen mid-session.
//
// The supported way to drive SDL's ivar is the hint
// SDL_HINT_IOS_HIDE_HOME_INDICATOR, whose value is assigned verbatim to
// homeIndicatorHidden. We set it to "2" so the indicator hides AND the
// bottom/side edges are deferred — the user must swipe twice to leave.

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    // Hide the home indicator (value 1) AND defer the system screen-edge
    // gestures (value 2) so a single bottom swipe is captured by scrcpy
    // instead of bouncing to the iOS home screen. SDL's hint callback
    // updates its viewcontroller and calls the setNeedsUpdate methods.
    SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "2");

    // Initialize the ScrappyMenuView with appropriate size
    __weak typeof(self) weakSelf = self;
    self.menuView = [[ScrcpyMenuView alloc] initWithFrame:CGRectZero]; // Frame will be set correctly during initialization
    self.menuView.delegate = weakSelf;
    
    // 根据当前连接的设备类型配置菜单
    [self configureMenuForCurrentDeviceType];
    
    [self.menuView addToActiveWindow];
    
    // 监听键盘显示和隐藏的通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];

    // 监听 VNC 提示（例如：剪贴板同步成功）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleVNCTipNotification:)
                                                 name:kNotificationVNCClipboardSynced
                                               object:nil];

    // 监听远程设备方向变化通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleRemoteOrientationChanged:)
                                                 name:ScrcpyRemoteOrientationChangedNotification
                                               object:nil];

    // 监听断开连接通知，以便重置方向锁定
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDisconnectForOrientationReset:)
                                                 name:ScrcpyRequestDisconnectNotification
                                               object:nil];

    // 监听状态更新通知，检测断开连接状态
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleStatusUpdateForOrientationReset:)
                                                 name:ScrcpyStatusUpdatedNotificationName
                                               object:nil];

    // Re-sync SDL window size when the app/scene returns to foreground.
    // On iPad floating windows (Slide Over / Stage Manager) the system may
    // resize the underlying SDL window while we are backgrounded (e.g. user
    // pulls down Notification Center or switches apps). When we resume, our
    // view bounds may equal the cached g_lastKnownViewSize so the normal
    // layout-driven path short-circuits, leaving SDL's cached touch-mapping
    // rect stale and producing drifted touch coordinates.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAppDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    if (@available(iOS 13.0, *)) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleSceneDidActivate:)
                                                     name:UISceneDidActivateNotification
                                                   object:nil];
        // Slide Over hide-by-edge / restore does not always cycle through
        // DidActivate; it may only emit WillEnterForeground on the scene.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleSceneDidActivate:)
                                                     name:UISceneWillEnterForegroundNotification
                                                   object:nil];
    }

    // Window-visibility transitions cover the case where Slide Over slides
    // the window off-screen and back without changing scene activation state.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAppDidBecomeActive:)
                                                 name:UIWindowDidBecomeVisibleNotification
                                               object:nil];

    // Check if there's already a known remote orientation (frame arrived before viewDidAppear)
    // Apply it now since we missed the notification
    [self applyPendingRemoteOrientation];
}

#pragma mark - Foreground Re-activation

- (void)handleAppDidBecomeActive:(NSNotification *)notification {
    [self forceResyncSDLWindowSizeAfterForeground];
}

- (void)handleSceneDidActivate:(NSNotification *)notification {
    if (@available(iOS 13.0, *)) {
        UIScene *scene = notification.object;
        // Only react to the scene that owns this view controller's window
        if (scene && scene != self.view.window.windowScene) {
            return;
        }
    }
    [self forceResyncSDLWindowSizeAfterForeground];
}

- (void)forceResyncSDLWindowSizeAfterForeground {
    // Trigger a layout pass so self.view.bounds reflects any size adjustment
    // iOS may have applied while backgrounded, then force the SDL resync even
    // if the cached size compares equal.
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self notifySDLWindowSizeChangeForced:YES];
    [self updateDisplayLayerFrame];
}

-(void)applyPendingRemoteOrientation {
    // Check if remote orientation is already known (frames arrived before viewDidAppear)
    if (!IsRemoteOrientationKnown()) {
        NSLog(@"📱 [SDL_uikitviewcontroller] No pending remote orientation to apply");
        return;
    }

    int width = 0, height = 0;
    BOOL isLandscape = GetCurrentRemoteOrientation(&width, &height);

    NSLog(@"📱 [SDL_uikitviewcontroller] Applying pending remote orientation: %@ (%dx%d)",
          isLandscape ? @"Landscape" : @"Portrait", width, height);

    // Force orientation change
    [self forceOrientationToLandscape:isLandscape];

    // Schedule layout updates
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateDisplayLayerFrame];
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateDisplayLayerFrame];
    });
}

-(void)viewWillUnload
{
    [super viewWillUnload];

    // Unlock orientation when view is about to be unloaded
    [self unlockOrientation];

    // Restore default home-indicator / edge-gesture behaviour via SDL's
    // hint (value 0 = indicator shown, edges not deferred).
    SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "0");
    NSLog(@"Reset ViewControllers HomeIndicatorAutoHidden.");
}

- (void)dealloc
{
    // 移除通知观察者
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - VNC Tips

-(void)handleVNCTipNotification:(NSNotification *)notification {
    BOOL isEmpty = [notification.userInfo[kKeyIsEmpty] boolValue];
    NSString *message = isEmpty
        ? NSLocalizedString(@"No Local Clipboard Content", nil)
        : NSLocalizedString(@"Synced Local Clipboard Content", nil);

    // Show a concise, one-line tip without exposing clipboard contents
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}

#pragma mark - Remote Orientation Change

-(void)handleRemoteOrientationChanged:(NSNotification *)notification {
    BOOL isLandscape = [notification.userInfo[@"isLandscape"] boolValue];
    int remoteWidth = [notification.userInfo[@"width"] intValue];
    int remoteHeight = [notification.userInfo[@"height"] intValue];
    BOOL isFirstFrame = [notification.userInfo[@"isFirstFrame"] boolValue];

    NSLog(@"📱 [SDL_uikitviewcontroller] Remote orientation %@: %@ (%dx%d)",
          isFirstFrame ? @"initial" : @"changed",
          isLandscape ? @"Landscape" : @"Portrait", remoteWidth, remoteHeight);

    // Force orientation change
    [self forceOrientationToLandscape:isLandscape];

    // Schedule layout update after a short delay to ensure orientation change completes
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateDisplayLayerFrame];
    });

    // Also update after a longer delay for iOS animation completion
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateDisplayLayerFrame];
    });
}

-(void)updateDisplayLayerFrame {
    // Force layout update
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];

    // Explicitly update all AVSampleBufferDisplayLayer frames
    for (CALayer *layer in self.view.layer.sublayers) {
        if ([layer isKindOfClass:AVSampleBufferDisplayLayer.class]) {
            CGRect newFrame = self.view.bounds;
            if (!CGRectEqualToRect(layer.frame, newFrame)) {
                NSLog(@"📱 [SDL_uikitviewcontroller] Updating display layer frame: %@ -> %@",
                      NSStringFromCGRect(layer.frame), NSStringFromCGRect(newFrame));
                layer.frame = newFrame;
            }
        }
    }
}

-(void)forceOrientationToLandscape:(BOOL)landscape {
    UIWindowScene *windowScene = self.view.window.windowScene;
    if (!windowScene) {
        NSLog(@"⚠️ [SDL_uikitviewcontroller] No window scene available for orientation change");
        return;
    }

    // Set the locked orientation mask to prevent local device rotation
    UIInterfaceOrientationMask targetMask = landscape
        ? UIInterfaceOrientationMaskLandscape
        : UIInterfaceOrientationMaskPortrait;

    [self setLockedOrientationMask:targetMask];
    [self setOrientationLockEnabled:YES];

    NSLog(@"🔒 [SDL_uikitviewcontroller] Orientation locked to: %@", landscape ? @"Landscape" : @"Portrait");

    // Check if current orientation already matches target
    UIInterfaceOrientation currentOrientation = windowScene.interfaceOrientation;
    BOOL currentIsLandscape = UIInterfaceOrientationIsLandscape(currentOrientation);

    if (currentIsLandscape == landscape) {
        NSLog(@"📱 [SDL_uikitviewcontroller] Orientation already matches: %@, updating layer frame",
              landscape ? @"Landscape" : @"Portrait");
        // Still update the layer frame in case it's not correct
        [self updateDisplayLayerFrame];
        return;
    }

    if (@available(iOS 16.0, *)) {
        // iOS 16+ uses requestGeometryUpdate
        UIWindowSceneGeometryPreferencesIOS *preferences =
            [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:targetMask];

        __weak typeof(self) weakSelf = self;
        [windowScene requestGeometryUpdateWithPreferences:preferences
                                             errorHandler:^(NSError * _Nonnull error) {
            NSLog(@"❌ [SDL_uikitviewcontroller] Failed to update geometry: %@", error.localizedDescription);
            // Still try to update layer frame on error
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf updateDisplayLayerFrame];
            });
        }];

        // Also update the view controller to ensure it reports the correct orientations
        [self setNeedsUpdateOfSupportedInterfaceOrientations];

        NSLog(@"📱 [SDL_uikitviewcontroller] Requested orientation change to %@ (iOS 16+)",
              landscape ? @"Landscape" : @"Portrait");
    } else {
        // iOS 15 and earlier - use device orientation value setting
        UIDeviceOrientation targetOrientation = landscape
            ? UIDeviceOrientationLandscapeLeft
            : UIDeviceOrientationPortrait;

        // Force orientation using private API (setValue:forKey:)
        [[UIDevice currentDevice] setValue:@(targetOrientation) forKey:@"orientation"];

        // Trigger orientation change
        [UIViewController attemptRotationToDeviceOrientation];

        NSLog(@"📱 [SDL_uikitviewcontroller] Forced orientation change to %@ (iOS 15-)",
              landscape ? @"Landscape" : @"Portrait");
    }
}

-(void)unlockOrientation {
    // Disable orientation lock
    [self setOrientationLockEnabled:NO];
    [self setLockedOrientationMask:UIInterfaceOrientationMaskAll];

    // Reset orientation tracking state in runtime
    ResetScrcpyOrientationTracking();

    NSLog(@"🔓 [SDL_uikitviewcontroller] Orientation unlocked, following local device orientation");

    // Update supported orientations
    if (@available(iOS 16.0, *)) {
        [self setNeedsUpdateOfSupportedInterfaceOrientations];

        // Request geometry update to allow all orientations
        UIWindowScene *windowScene = self.view.window.windowScene;
        if (windowScene) {
            UIWindowSceneGeometryPreferencesIOS *preferences =
                [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskAll];

            [windowScene requestGeometryUpdateWithPreferences:preferences
                                                 errorHandler:^(NSError * _Nonnull error) {
                NSLog(@"⚠️ [SDL_uikitviewcontroller] Failed to unlock geometry: %@", error.localizedDescription);
            }];
        }
    } else {
        [UIViewController attemptRotationToDeviceOrientation];
    }
}

-(void)handleDisconnectForOrientationReset:(NSNotification *)notification {
    NSLog(@"📱 [SDL_uikitviewcontroller] Disconnect requested, unlocking orientation");
    // Dispatch to main thread since this may be called from background
    if ([NSThread isMainThread]) {
        [self unlockOrientation];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self unlockOrientation];
        });
    }
}

-(void)handleStatusUpdateForOrientationReset:(NSNotification *)notification {
    NSNumber *statusNumber = notification.userInfo[@"status"];
    if (!statusNumber) return;

    int status = [statusNumber intValue];

    // Check if status is disconnected (ScrcpyStatusDisconnected = 0)
    if (status == 0) {
        NSLog(@"📱 [SDL_uikitviewcontroller] Status changed to disconnected, unlocking orientation");
        // Dispatch to main thread since this notification comes from background thread
        if ([NSThread isMainThread]) {
            [self unlockOrientation];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self unlockOrientation];
            });
        }
    }
}

#pragma mark - Keyboard Notifications

- (void)keyboardWillShow:(NSNotification *)notification {
    // Native dialogs (including PIN entry) must receive their own keyboard touches.
    if (self.presentedViewController) { return; }
    // 当键盘显示时，创建并显示输入遮罩视图，并在键盘上方显示工具栏
    if (!self.inputMaskView) {
        self.inputMaskView = [[ScrcpyInputMaskView alloc] initWithFrame:self.view.bounds];
    }
    [self.inputMaskView showInView:self.view];

    // 读取键盘最终位置与动画参数
    NSDictionary *info = notification.userInfo;
    CGRect kbFrameScreen = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [info[UIKeyboardAnimationCurveUserInfoKey] integerValue];

    // 将键盘frame转换到当前视图坐标系
    // Convert to window coordinates so the overlay (added to window) can align correctly
    CGRect kbFrameInView = [self.view.window convertRect:kbFrameScreen fromWindow:nil];

    // 获取当前设备类型（adb/vnc）
    SessionConnectionManager *connectionManager = [SessionConnectionManager shared];
    NSString *deviceTypeString = [connectionManager getCurrentDeviceType];

    // 更新并动画展示工具栏
    [self.inputMaskView showKeyboardToolbarAboveKeyboardFrame:kbFrameInView
                                              deviceTypeString:deviceTypeString
                                                     duration:duration
                                                         curve:curve];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    // 当键盘隐藏时，隐藏工具栏并移除输入遮罩视图
    //
    // Guard: if our view controller is no longer in a window (the session is
    // exiting while the keyboard is still minimising) the inputMaskView is
    // about to be detached from a window that no longer participates in any
    // AutoLayout engine. Running the hide animation here can rethrow an
    // NSISEngine exception from inside withBehaviors:performModifications:
    // (field crash "Crashed when exiting port with minimized keyboard").
    // Drop the animation in that case — viewDidDisappear/dealloc removes the
    // overlay anyway.
    if (!self.view.window || !self.inputMaskView.window) {
        return;
    }
    [self.inputMaskView hideKeyboardToolbarWithNotification:notification];
    [self.inputMaskView hide];
}

#pragma mark - Menu Configuration

- (void)configureMenuForCurrentDeviceType {
    // 获取当前设备类型
    SessionConnectionManager *connectionManager = [SessionConnectionManager shared];
    NSString *deviceTypeString = [connectionManager getCurrentDeviceType];
    
    // 使用便利方法转换设备类型
    ScrcpyDeviceType deviceType = [ScrcpyMenuView deviceTypeFromString:deviceTypeString];
    
    // 记录日志
    if (deviceTypeString) {
        NSLog(@"🎛️ [SDL_uikitviewcontroller] Configuring menu for %@ device", deviceTypeString);
    } else {
        NSLog(@"⚠️ [SDL_uikitviewcontroller] No current device type found, using ADB default");
    }
    
    // 配置菜单视图
    [self.menuView configureForDeviceType:deviceType];
}

#pragma mark - ScrappyMenuViewDelegate

- (void)didTapBackButton {
    // 发送 Back 按键事件 (Ctrl+B)
    ScrcpySendKeycodeEvent(SDL_SCANCODE_B, SDLK_B, SDL_KMOD_LCTRL);
}

- (void)didTapHomeButton {
    // 发送 Home 按键事件 (Ctrl+H)
    ScrcpySendKeycodeEvent(SDL_SCANCODE_H, SDLK_H, SDL_KMOD_LCTRL);
}

- (void)didTapSwitchButton {
    // 发送 Switch 按键事件 (Ctrl+S)
    ScrcpySendKeycodeEvent(SDL_SCANCODE_S, SDLK_S, SDL_KMOD_LCTRL);
}

- (void)didTapKeyboardButton {
    // Toggle keyboard
    SDL_StartTextInput(SDL_GetKeyboardFocus());
}

- (void)didTapActionsButton {
    // 显示功能开发中的提示
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Actions", @"Actions title") 
                                                                   message:NSLocalizedString(@"This feature is under development, please wait.", @"WIP message") 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK button") 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:nil];
    
    [alert addAction:okAction];
    
    // 在主线程中显示Alert
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)didTapDisconnectButton {
    // Post notification to disconnect
    [[NSNotificationCenter defaultCenter] postNotificationName:ScrcpyRequestDisconnectNotification object:nil];
}

#pragma mark - VNC Zoom Delegate Methods

- (void)didPinchWithScale:(CGFloat)scale {
    NSLog(@"🔍 [SDL_uikitviewcontroller] VNC pinch with scale: %.2f", scale);
    
    // 发送VNC缩放通知给VNCClient处理
    NSDictionary *userInfo = @{
        @"scale": @(scale),
        @"centerX": @(0.5), // 默认屏幕中心，后续可改为实际触摸中心
        @"centerY": @(0.5),
        @"isFinished": @(NO)
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyVNCZoomNotification" object:nil userInfo:userInfo];
}

- (void)didPinchWithScale:(CGFloat)scale centerX:(CGFloat)centerX centerY:(CGFloat)centerY {
    NSLog(@"🔍 [SDL_uikitviewcontroller] VNC pinch with scale: %.2f, center: (%.3f, %.3f)", scale, centerX, centerY);
    
    // 发送VNC缩放通知给VNCClient处理（包含实际触摸中心点）
    NSDictionary *userInfo = @{
        @"scale": @(scale),
        @"centerX": @(centerX),
        @"centerY": @(centerY),
        @"isFinished": @(NO)
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyVNCZoomNotification" object:nil userInfo:userInfo];
}

- (void)didPinchEndWithFinalScale:(CGFloat)finalScale {
    NSLog(@"🔍 [SDL_uikitviewcontroller] VNC pinch ended with final scale: %.2f", finalScale);
    
    // 发送VNC缩放结束通知给VNCClient处理
    NSDictionary *userInfo = @{
        @"scale": @(finalScale),
        @"centerX": @(0.5), // 默认屏幕中心，后续可改为实际触摸中心
        @"centerY": @(0.5),
        @"isFinished": @(YES)
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyVNCZoomNotification" object:nil userInfo:userInfo];
}

- (void)didPinchEndWithFinalScale:(CGFloat)finalScale centerX:(CGFloat)centerX centerY:(CGFloat)centerY {
    NSLog(@"🔍 [SDL_uikitviewcontroller] VNC pinch ended with final scale: %.2f, center: (%.3f, %.3f)", finalScale, centerX, centerY);
    
    // 发送VNC缩放结束通知给VNCClient处理（包含实际触摸中心点）
    NSDictionary *userInfo = @{
        @"scale": @(finalScale),
        @"centerX": @(centerX),
        @"centerY": @(centerY),
        @"isFinished": @(YES)
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyVNCZoomNotification" object:nil userInfo:userInfo];
}

#pragma mark - VNC Drag Gesture Delegate

- (void)didDragWithState:(NSString *)state location:(CGPoint)location viewSize:(CGSize)viewSize {
    NSLog(@"🎯 [SDL_uikitviewcontroller] VNC drag - state: %@, location: (%.1f, %.1f), viewSize: (%.1f, %.1f)", 
          state, location.x, location.y, viewSize.width, viewSize.height);
    
    // 发送VNC拖拽通知给VNCClient处理
    NSDictionary *userInfo = @{
        @"state": state,
        @"location": [NSValue valueWithCGPoint:location],
        @"viewSize": [NSValue valueWithCGSize:viewSize]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyVNCDragNotification" object:nil userInfo:userInfo];
}

@end
