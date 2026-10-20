#import "ScrcpyInputMaskView.h"
#import <SDL3/SDL_system.h>
#import <SDL3/SDL_events.h>
#import "ScrcpyConstants.h"

@interface ScrcpyInputMaskView () <UIGestureRecognizerDelegate>
// Toolbar UI
@property (nonatomic, strong) UIVisualEffectView *toolbarView;
@property (nonatomic, strong) UIScrollView *keysScrollView;
@property (nonatomic, strong) UIButton *hideKeyboardButton;
@property (nonatomic, strong) NSArray<UIButton *> *keyButtons;
@property (nonatomic, strong) UIButton *btnMeta;
@property (nonatomic, strong) UIButton *btnCtrl;
@property (nonatomic, strong) UIButton *btnAlt;
@property (nonatomic, strong) UIButton *btnShift;
@property (nonatomic, strong) UIButton *btnTab;
@property (nonatomic, strong) UIButton *btnEsc;
@property (nonatomic, strong) UIButton *pinButton;
@property (nonatomic, assign) BOOL toolbarVisible;
@property (nonatomic, copy) NSString *currentDeviceType; // "adb" or "vnc"

// Modifier states
@property (nonatomic, assign) BOOL candMeta;
@property (nonatomic, assign) BOOL lockMeta;
@property (nonatomic, assign) BOOL candCtrl;
@property (nonatomic, assign) BOOL lockCtrl;
@property (nonatomic, assign) BOOL candAlt;
@property (nonatomic, assign) BOOL lockAlt;
@property (nonatomic, assign) BOOL candShift;
@property (nonatomic, assign) BOOL lockShift;
@property (nonatomic, assign) CFTimeInterval lastTapMeta;
@property (nonatomic, assign) CFTimeInterval lastTapCtrl;
@property (nonatomic, assign) CFTimeInterval lastTapAlt;
@property (nonatomic, assign) CFTimeInterval lastTapShift;
@end

// Layout constants (compact)
static const CGFloat kToolbarHeight = 38.0;
static const CGFloat kToolbarHorizontalPadding = 6.0;
static const CGFloat kKeyButtonHeight = 28.0;
static const CGFloat kKeyButtonMinWidth = 40.0;
static const CGFloat kKeyButtonSpacing = 6.0;
// Hide button will display an icon only

@implementation ScrcpyInputMaskView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Setup view
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        
        // Add tap gesture
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc]
                                             initWithTarget:self
                                             action:@selector(handleTap:)];
        tapGesture.cancelsTouchesInView = NO; // allow buttons/scroll to receive touches
        tapGesture.delegate = self; // filter touches on toolbar
        [self addGestureRecognizer:tapGesture];
        
        // Register for orientation change notifications
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(orientationDidChange:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];

        // Observe VNC notification to clear candidate modifier state after a non-modifier key is used
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onClearCandidateModifiers:)
                                                     name:kNotificationVNCClearCandidateModifiers
                                                   object:nil];

        // Prepare toolbar (added later to hierarchy)
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
        self.toolbarView = [[UIVisualEffectView alloc] initWithEffect:blur];
        self.toolbarView.clipsToBounds = YES;
        self.toolbarView.layer.cornerRadius = 10.0;
        self.toolbarView.alpha = 0.0;

        self.keysScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        self.keysScrollView.showsHorizontalScrollIndicator = NO;
        self.keysScrollView.showsVerticalScrollIndicator = NO;
        [self.toolbarView.contentView addSubview:self.keysScrollView];

        self.hideKeyboardButton = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *hideIcon = [UIImage systemImageNamed:@"keyboard.chevron.compact.down"] ?: [UIImage systemImageNamed:@"keyboard"]; // fallback
        [self.hideKeyboardButton setImage:hideIcon forState:UIControlStateNormal];
        self.hideKeyboardButton.tintColor = [UIColor labelColor];
        self.hideKeyboardButton.accessibilityLabel = NSLocalizedString(@"Hide Keyboard", nil);
        self.hideKeyboardButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
        self.hideKeyboardButton.layer.cornerRadius = 8.0;
        self.hideKeyboardButton.contentEdgeInsets = UIEdgeInsetsMake(4, 4, 4, 4);
        [self.hideKeyboardButton addTarget:self action:@selector(handleHideKeyboardTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.toolbarView.contentView addSubview:self.hideKeyboardButton];

        self.pinButton = [self createKeyButtonWithTitle:@"PIN" action:@selector(handlePIN)];
        self.pinButton.accessibilityLabel = NSLocalizedString(@"Send PIN", nil);
        [self.toolbarView.contentView addSubview:self.pinButton];

        // Pre-create key buttons for VNC (include Shift as modifier)
        self.btnMeta = [self createKeyButtonWithTitle:@"Meta" action:@selector(handleMeta)];
        self.btnCtrl = [self createKeyButtonWithTitle:@"Ctrl" action:@selector(handleCtrl)];
        self.btnAlt  = [self createKeyButtonWithTitle:@"Alt"  action:@selector(handleAlt)];
        self.btnShift= [self createKeyButtonWithTitle:@"Shift" action:@selector(handleShift)];
        self.btnTab  = [self createKeyButtonWithTitle:@"Tab"  action:@selector(handleTab)];
        self.btnEsc  = [self createKeyButtonWithTitle:@"Esc"  action:@selector(handleEsc)];
        self.keyButtons = @[ self.btnMeta, self.btnCtrl, self.btnAlt, self.btnShift, self.btnTab, self.btnEsc ];
    }
    return self;
}

- (void)dealloc {
    // Remove notification observer
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)orientationDidChange:(NSNotification *)notification {
    // Update frame when device orientation changes
    if (self.superview) {
        self.frame = self.superview.bounds;
    }
}

- (void)showInView:(UIView *)parentView {
    // Remove from any previous superview
    [self removeFromSuperview];

    // Prefer attaching to the window so we are above overlays added to window
    UIWindow *window = parentView.window ?: [UIApplication sharedApplication].keyWindow;
    if (!window) { window = UIApplication.sharedApplication.windows.firstObject; }

    // Set frame to match window bounds
    self.frame = window.bounds;
    // Ensure we render and hit-test above other window subviews
    self.layer.zPosition = 1000.0;

    // Add to window and bring to front
    [window addSubview:self];
    [window bringSubviewToFront:self];

    // Ensure toolbar (if created) is at front inside self
    if (self.toolbarView) {
        self.toolbarView.layer.zPosition = 1001.0;
        [self bringSubviewToFront:self.toolbarView];
    }

    // Make sure it's initially visible
    self.alpha = 1.0;
}

- (void)hide {
    // If we are already detached (e.g. the session view-controller is being
    // torn down while the keyboard is still minimising) skip the animation —
    // running an animateWithDuration: against a view with no window can
    // rethrow from NSISEngine.withBehaviors:performModifications: when the
    // constraint engine has already been disconnected.
    if (!self.window || !self.superview) {
        [self removeFromSuperview];
        return;
    }
    [UIView animateWithDuration:0.1 animations:^{
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    CGPoint p = [gesture locationInView:self];
    if (self.toolbarView.alpha > 0.0 && CGRectContainsPoint(self.toolbarView.frame, p)) {
        // Ignore taps on toolbar area
        return;
    }
    NSLog(@"Input mask background tapped - stopping text input");
    SDL_StopTextInput(SDL_GetKeyboardFocus());
    [self hide];
}

- (void)handlePIN {
    UIViewController *presenter = self.window.rootViewController;
    while (presenter.presentedViewController) { presenter = presenter.presentedViewController; }
    SDL_StopTextInput(SDL_GetKeyboardFocus());
    [self hide];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyPresentPINEntry" object:presenter];
}

- (void)onClearCandidateModifiers:(NSNotification *)note {
    BOOL changed = self.candMeta || self.candCtrl || self.candAlt || self.candShift;
    if (!changed) { return; }
    self.candMeta = NO; self.candCtrl = NO; self.candAlt  = NO; self.candShift= NO;
    [self postModifierStateUpdate];
    [self refreshModifierButtonsAppearance];
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // Do not start the background tap recognizer when tapping inside the toolbar (or its subviews)
    UIView *view = touch.view;
    if (!view) { return YES; }
    if (self.toolbarView && (view == self.toolbarView || [view isDescendantOfView:self.toolbarView])) {
        return NO;
    }
    return YES;
}

// MARK: - Toolbar helpers

- (UIButton *)createKeyButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    // Only deepen title color on states; no extra background region
    btn.backgroundColor = UIColor.clearColor;
    btn.layer.cornerRadius = 6.0; // subtle rounded chip when highlighted
    btn.clipsToBounds = YES;
    btn.contentEdgeInsets = UIEdgeInsetsMake(2, 6, 2, 6);
    [btn setTitleColor:[[UIColor labelColor] colorWithAlphaComponent:0.72] forState:UIControlStateNormal];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)ensureToolbarInHierarchy {
    if (!self.toolbarView.superview) {
        [self addSubview:self.toolbarView];
    }
}

- (void)layoutToolbarWithinBounds:(CGRect)bounds keyboardFrame:(CGRect)kbFrameInSelf {
    CGFloat width = bounds.size.width;
    CGFloat toolbarY = CGRectGetMinY(kbFrameInSelf) - kToolbarHeight - 4.0; // compact gap above keyboard
    if (toolbarY < bounds.origin.y + 8.0) {
        toolbarY = bounds.origin.y + 8.0;
    }
    CGRect tbFrame = CGRectMake(kToolbarHorizontalPadding,
                                toolbarY,
                                width - kToolbarHorizontalPadding * 2,
                                kToolbarHeight);

    // Configure keys based on device type first
    BOOL isADB = [self.currentDeviceType.lowercaseString isEqualToString:@"adb"];

    self.pinButton.hidden = !isADB;
    if (isADB) {
        // Keep PIN input available even when Android protects the video.
        CGFloat hideButtonW = kKeyButtonHeight;
        CGFloat compactWidth = hideButtonW + 64.0; // inner padding total
        CGFloat tbX = CGRectGetMaxX(bounds) - compactWidth - kToolbarHorizontalPadding;
        self.toolbarView.frame = CGRectMake(tbX, toolbarY, compactWidth, kToolbarHeight);

        CGFloat hideY = (kToolbarHeight - kKeyButtonHeight) / 2.0;
        CGFloat hideX = compactWidth - hideButtonW - 6.0;
        self.hideKeyboardButton.frame = CGRectMake(hideX, hideY, hideButtonW, kKeyButtonHeight);

        self.pinButton.frame = CGRectMake(6, hideY, 46, kKeyButtonHeight);

        // No keys area
        self.keysScrollView.frame = CGRectZero;
        self.keysScrollView.contentSize = CGSizeZero;
        for (UIView *v in self.keysScrollView.subviews) { [v removeFromSuperview]; }
        self.keysScrollView.hidden = YES;
        self.keysScrollView.userInteractionEnabled = NO;
        return;
    }

    // Non-ADB: full-width toolbar
    self.toolbarView.frame = tbFrame;

    // Layout hide button on right
    // Icon-only button: square size based on key height
    CGFloat hideButtonW = kKeyButtonHeight;
    CGFloat hideX = CGRectGetWidth(tbFrame) - hideButtonW - 6.0;
    CGFloat hideY = (kToolbarHeight - kKeyButtonHeight) / 2.0;
    self.hideKeyboardButton.frame = CGRectMake(hideX, hideY, hideButtonW, kKeyButtonHeight);

    // Layout scroll view to take remaining left area
    CGFloat scrollX = 6.0;
    CGFloat scrollW = MAX(0, hideX - scrollX - 6.0);
    self.keysScrollView.frame = CGRectMake(scrollX, 0, scrollW, kToolbarHeight);

    // Add keys to scroll area
    self.keysScrollView.hidden = NO;
    self.keysScrollView.userInteractionEnabled = YES;
    for (UIView *v in self.keysScrollView.subviews) { [v removeFromSuperview]; }
    CGFloat x = 0;
    NSArray<UIButton *> *buttons = self.keyButtons;
    for (UIButton *btn in buttons) {
        CGSize s = [btn sizeThatFits:CGSizeMake(CGFLOAT_MAX, kKeyButtonHeight)];
        CGFloat w = MAX(kKeyButtonMinWidth, s.width + 12.0);
        btn.frame = CGRectMake(x, (kToolbarHeight - kKeyButtonHeight)/2.0, w, kKeyButtonHeight);
        [self.keysScrollView addSubview:btn];
        x += w + kKeyButtonSpacing;
    }
    self.keysScrollView.contentSize = CGSizeMake(MAX(scrollW, x), kToolbarHeight);
}

- (void)showKeyboardToolbarAboveKeyboardFrame:(CGRect)keyboardFrame
                             deviceTypeString:(nullable NSString *)deviceTypeString
                                     duration:(NSTimeInterval)duration
                                         curve:(UIViewAnimationCurve)curve {
    self.currentDeviceType = deviceTypeString ?: @"vnc";
    [self ensureToolbarInHierarchy];
    // If our superview is a window and the frame is in window coords, use directly;
    // otherwise convert from superview's coords into self.
    CGRect kbInSelf = keyboardFrame;
    if (self.superview) {
        kbInSelf = [self.superview convertRect:keyboardFrame toView:self];
    }
    [self layoutToolbarWithinBounds:self.bounds keyboardFrame:kbInSelf];

    UIViewAnimationOptions options = (UIViewAnimationOptions)(curve << 16) | UIViewAnimationOptionBeginFromCurrentState;
    [UIView animateWithDuration:MAX(0.0, duration)
                          delay:0
                        options:options
                     animations:^{
        self.toolbarView.alpha = 1.0;
    } completion:^(BOOL finished) {
        self.toolbarVisible = YES;
    }];
}

- (void)hideKeyboardToolbarWithNotification:(NSNotification *)notification {
    // Same guard as -hide: skip the toolbar fade when we're already off-window
    // so we don't pump the AutoLayout engine after it's been disconnected.
    if (!self.window || !self.toolbarView) {
        self.toolbarVisible = NO;
        return;
    }
    NSDictionary *info = notification.userInfo ?: @{};
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [info[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    UIViewAnimationOptions options = (UIViewAnimationOptions)(curve << 16) | UIViewAnimationOptionBeginFromCurrentState;
    [UIView animateWithDuration:MAX(0.0, duration)
                          delay:0
                        options:options
                     animations:^{
        self.toolbarView.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.toolbarVisible = NO;
    }];
}

// MARK: - Button Actions

- (void)handleHideKeyboardTapped {
    SDL_StopTextInput(SDL_GetKeyboardFocus());
    [self hide];
}

- (void)pushSDLKeyDownWithScancode:(SDL_Scancode)scancode keycode:(SDL_Keycode)keycode {
    // SDL3: SDL_KeyboardEvent.keysym was flattened into the event itself
    // (key / scancode / mod), .state was replaced by .down (bool).
    SDL_Event evt;
    SDL_memset(&evt, 0, sizeof(evt));
    evt.type = SDL_EVENT_KEY_DOWN;
    evt.key.type = SDL_EVENT_KEY_DOWN;
    evt.key.scancode = scancode;
    evt.key.key = keycode;
    evt.key.mod = SDL_KMOD_NONE;
    evt.key.down = true;
    evt.key.repeat = false;
    SDL_PushEvent(&evt);
}

- (void)pushSDLKeyUpWithScancode:(SDL_Scancode)scancode keycode:(SDL_Keycode)keycode {
    SDL_Event evt;
    SDL_memset(&evt, 0, sizeof(evt));
    evt.type = SDL_EVENT_KEY_UP;
    evt.key.type = SDL_EVENT_KEY_UP;
    evt.key.scancode = scancode;
    evt.key.key = keycode;
    evt.key.mod = SDL_KMOD_NONE;
    evt.key.down = false;
    evt.key.repeat = false;
    SDL_PushEvent(&evt);
}

- (void)sendKeyWithActiveModifiers:(SDL_Scancode)scancode keycode:(SDL_Keycode)keycode {
    // Collect active modifiers from local state
    BOOL modsMeta = (self.lockMeta || self.candMeta);
    BOOL modsCtrl = (self.lockCtrl || self.candCtrl);
    BOOL modsAlt  = (self.lockAlt  || self.candAlt);
    BOOL modsShift= (self.lockShift|| self.candShift);

    // Notify VNC that this key is already combined (one-shot)
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCNextKeyAlreadyCombined object:nil];

    if (modsMeta) { [self pushSDLKeyDownWithScancode:SDL_SCANCODE_LGUI  keycode:SDLK_LGUI]; }
    if (modsCtrl) { [self pushSDLKeyDownWithScancode:SDL_SCANCODE_LCTRL keycode:SDLK_LCTRL]; }
    if (modsAlt)  { [self pushSDLKeyDownWithScancode:SDL_SCANCODE_LALT  keycode:SDLK_LALT]; }
    if (modsShift){ [self pushSDLKeyDownWithScancode:SDL_SCANCODE_LSHIFT keycode:SDLK_LSHIFT]; }

    [self pushSDLKeyDownWithScancode:scancode keycode:keycode];
    [self pushSDLKeyUpWithScancode:scancode keycode:keycode];

    if (modsShift){ [self pushSDLKeyUpWithScancode:SDL_SCANCODE_LSHIFT keycode:SDLK_LSHIFT]; }
    if (modsAlt)  { [self pushSDLKeyUpWithScancode:SDL_SCANCODE_LALT  keycode:SDLK_LALT]; }
    if (modsCtrl) { [self pushSDLKeyUpWithScancode:SDL_SCANCODE_LCTRL keycode:SDLK_LCTRL]; }
    if (modsMeta) { [self pushSDLKeyUpWithScancode:SDL_SCANCODE_LGUI  keycode:SDLK_LGUI]; }

    // Clear candidate modifiers after one use (both local and store)
    self.candMeta = NO; self.candCtrl = NO; self.candAlt = NO; self.candShift = NO;
    [self postModifierStateUpdate];
    [self refreshModifierButtonsAppearance];
}

- (void)toggleModifierCandidateOrLock:(NSString *)whichButton lastTap:(CFTimeInterval *)lastTap cand:(BOOL *)cand lock:(BOOL *)lock button:(UIButton *)button {
    CFTimeInterval now = CACurrentMediaTime();
    BOOL isDouble = (*lastTap > 0 && (now - *lastTap) < 0.35);
    *lastTap = now;
    if (isDouble) {
        // Toggle lock, clear candidate when locking on
        *lock = !*lock;
        if (*lock) { *cand = NO; }
    } else {
        // Single tap: if locked -> unlock; else toggle candidate
        if (*lock) {
            *lock = NO;
        } else {
            *cand = !*cand;
        }
    }
    // Notify VNC client of updated modifier state
    [self postModifierStateUpdate];
    [self refreshModifierButtonsAppearance];
}

- (void)refreshModifierButtonsAppearance {
    // Visuals: add light background for candidate, stronger for locked
    // Read from local state for UI
    void (^style)(UIButton *, BOOL, BOOL) = ^(UIButton *btn, BOOL cand, BOOL lock){
        // Make candidate lighter and locked deeper as requested
        CGFloat titleAlpha = lock ? 1.0 : (cand ? 0.82 : 0.72);
        [btn setTitleColor:[[UIColor labelColor] colorWithAlphaComponent:titleAlpha] forState:UIControlStateNormal];
        if (lock) {
            // Deeper background for locked
            btn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.38];
        } else if (cand) {
            // Even lighter background for one-shot candidate
            btn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
        } else {
            btn.backgroundColor = UIColor.clearColor;
        }
    };
    style(self.btnMeta,  self.candMeta,  self.lockMeta);
    style(self.btnCtrl,  self.candCtrl,  self.lockCtrl);
    style(self.btnAlt,   self.candAlt,   self.lockAlt);
    style(self.btnShift, self.candShift, self.lockShift);
}

- (void)postModifierStateUpdate {
    NSDictionary *userInfo = @{ 
        @"lockMeta": @(self.lockMeta),
        @"lockCtrl": @(self.lockCtrl),
        @"lockAlt":  @(self.lockAlt),
        @"lockShift":@(self.lockShift),
        @"candMeta": @(self.candMeta),
        @"candCtrl": @(self.candCtrl),
        @"candAlt":  @(self.candAlt),
        @"candShift":@(self.candShift)
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCModifierStateUpdated object:nil userInfo:userInfo];
}

- (void)handleMeta { [self toggleModifierCandidateOrLock:@"meta" lastTap:&_lastTapMeta cand:&_candMeta lock:&_lockMeta button:self.btnMeta]; }
- (void)handleCtrl { [self toggleModifierCandidateOrLock:@"ctrl" lastTap:&_lastTapCtrl cand:&_candCtrl lock:&_lockCtrl button:self.btnCtrl]; }
- (void)handleAlt  { [self toggleModifierCandidateOrLock:@"alt"  lastTap:&_lastTapAlt  cand:&_candAlt  lock:&_lockAlt  button:self.btnAlt]; }
- (void)handleShift{ [self toggleModifierCandidateOrLock:@"shift"lastTap:&_lastTapShift cand:&_candShift lock:&_lockShift button:self.btnShift]; }

- (void)handleTab { [self sendKeyWithActiveModifiers:SDL_SCANCODE_TAB keycode:SDLK_TAB]; }
- (void)handleEsc { [self sendKeyWithActiveModifiers:SDL_SCANCODE_ESCAPE keycode:SDLK_ESCAPE]; }

@end 
