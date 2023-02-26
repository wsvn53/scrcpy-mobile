//
//  KeysViewController.m
//  scrcpy-ios
//
//  Created by Ethan on 27/12/22.
//

#import "KeysViewController.h"
#import "CVCreate.h"
#import "ScrcpyTextField.h"
#import "ScrcpyClient.h"
#import "MBProgressHUD.h"

int adb_auth_key_generate(const char* filename);

@interface KeysViewController ()
@property (nonatomic, strong)   UITextView  *keyTextView;
@property (nonatomic, strong)   UITextView  *pubkeyTextView;
@end

@implementation KeysViewController

+(void)reload {
    NSLog(@"Reload UI");
    
    UINavigationController *nav = (UINavigationController *)UIApplication.sharedApplication.keyWindow.rootViewController;
    UINavigationController *keysNav = (UINavigationController *)nav.viewControllers.firstObject.presentedViewController;
    [keysNav setViewControllers:@[[self new]] animated:YES];
}

-(void)loadView {
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:(CGRectZero)];
    scrollView.alwaysBounceVertical = YES;
    self.view = scrollView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
}

-(void)setupViews {
    self.view.backgroundColor = UIColor.whiteColor;
    self.title = NSLocalizedString(@"Import/Export ADB Keys", nil);
    
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor systemGray6Color];
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    }
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Export", nil) style:(UIBarButtonItemStylePlain) target:self action:@selector(exportADBKey)];
    self.navigationItem.rightBarButtonItem.tintColor = UIColor.blackColor;
    
    CVCreate.UIStackView(@[
        CVCreate.UIView.size(CGSizeMake(0, 5)),
        CVCreate.UILabel.boldFontSize(15).text(NSLocalizedString(@"ADB Private Key(adbkey):", nil)).textColor(UIColor.darkGrayColor),
        CVCreate.withView(self.keyTextView).fontSize(15)
            .size((CGSize){0, 220})
            .text([self loadADBKey])
            .cornerRadius(5.f)
            .backgroundColor(UIColor.whiteColor)
            .textColor(UIColor.darkGrayColor)
            .border(UIColor.lightGrayColor, 1.f),
        CVCreate.UIView.size((CGSize){0, 1}),
        CVCreate.UILabel.boldFontSize(15).text(NSLocalizedString(@"ADB Public Key(adbkey.pub):", nil)).textColor(UIColor.darkGrayColor),
        CVCreate.withView(self.pubkeyTextView).fontSize(15)
            .size((CGSize){0, 220})
            .text([self loadADBPubKey])
            .cornerRadius(5.f)
            .backgroundColor(UIColor.whiteColor)
            .textColor(UIColor.darkGrayColor)
            .border(UIColor.lightGrayColor, 1.f),
        CVCreate.UIView.size((CGSize){0, 1}),
        CVCreate.UIButton.text(NSLocalizedString(@"Save Privatekey & Pubkey", nil)).boldFontSize(16)
            .addToView(self.view)
            .size(CGSizeMake(0, 45))
            .textColor(UIColor.whiteColor)
            .backgroundColor(UIColor.blackColor)
            .cornerRadius(6)
            .click(self, @selector(saveADBKey)),
        CVCreate.UIButton.text(NSLocalizedString(@"Generate New ADB Key Pair", nil)).boldFontSize(16)
            .addToView(self.view)
            .size(CGSizeMake(0, 45))
            .textColor(UIColor.blackColor)
            .backgroundColor(UIColor.whiteColor)
            .border(UIColor.grayColor, 2.f)
            .cornerRadius(6)
            .click(self, @selector(generateADBKeyPair)),
        CVCreate.UIButton.text(NSLocalizedString(@"Cancel", nil)).boldFontSize(16)
            .addToView(self.view)
            .size(CGSizeMake(0, 45))
            .textColor(UIColor.blackColor)
            .backgroundColor(UIColor.whiteColor)
            .border(UIColor.grayColor, 2.f)
            .cornerRadius(6)
            .click(self, @selector(cancel)),
    ])
    .axis(UILayoutConstraintAxisVertical)
    .spacing(15.f)
    .addToView(self.view)
    .topAnchor(self.view.topAnchor, 0)
    .bottomAnchor(self.view.bottomAnchor, 0)
    .widthAnchor(self.view.widthAnchor, -30)
    .centerXAnchor(self.view.centerXAnchor, 0);
    
    [self.view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(endEditing)]];
}

#pragma mark - Getters

-(UITextView *)keyTextView {
    return _keyTextView ? : ({
        _keyTextView = [[UITextView alloc] initWithFrame:(CGRectZero)];
        _keyTextView.autocorrectionType = UITextAutocorrectionTypeNo;
        _keyTextView.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _keyTextView;
    });
}

-(UITextView *)pubkeyTextView {
    return _pubkeyTextView ? : ({
        _pubkeyTextView = [[UITextView alloc] initWithFrame:(CGRectZero)];
        _pubkeyTextView.autocorrectionType = UITextAutocorrectionTypeNo;
        _pubkeyTextView.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _pubkeyTextView;
    });
}

#pragma mark - Utils

-(void)showAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Scrcpy Remote" message:message preferredStyle:(UIAlertControllerStyleAlert)];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:(UIAlertActionStyleCancel) handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - ADB Key Management

-(void)exportADBKey {
    // Export ADB Key to Local File
    UIDocumentPickerViewController *pickerController = [[UIDocumentPickerViewController alloc] initWithURLs:@[
        [NSURL fileURLWithPath:[self adbKeyPath]],
        [NSURL fileURLWithPath:[self adbPubKeyPath]],
    ] inMode:(UIDocumentPickerModeExportToService)];
    pickerController.delegate = (id<UIDocumentPickerDelegate>)self;
    [self presentViewController:pickerController animated:YES completion:nil];
}

-(NSString *)adbKeyPath {
    return [ScrcpyClient.sharedClient.adbHomePath stringByAppendingPathComponent:@".android/adbkey"];
}

-(NSString *)adbPubKeyPath {
    return [[self adbKeyPath] stringByAppendingString:@".pub"];
}

-(NSString *)loadADBKey {
    NSError *error = nil;
    NSString *adbKey = [NSString stringWithContentsOfFile:[self adbKeyPath] encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        [self showAlert:[NSString stringWithFormat:NSLocalizedString(@"Load ADB Key Failed: %@", nil), error]];
        return @"";
    }
    return adbKey;
}

-(NSString *)loadADBPubKey {
    NSError *error = nil;
    NSString *adbKey = [NSString stringWithContentsOfFile:[self adbPubKeyPath] encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        [self showAlert:[NSString stringWithFormat:NSLocalizedString(@"Load ADB PubKey Failed: %@", nil), error]];
        return @"";
    }
    return adbKey;
}

-(void)generateNewADBKey {
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    
    __weak typeof(self) weak_self = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        adb_auth_key_generate([weak_self adbKeyPath].UTF8String);
        dispatch_async(dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:weak_self.view animated:YES];
            
            // Update adbkey and pubkey
            weak_self.keyTextView.text = [self loadADBKey];
            weak_self.pubkeyTextView.text = [self loadADBPubKey];
            
            // Required restart app
            [weak_self showAlert:NSLocalizedString(@"New ADB key pairs GENERATED.\nPlease RESTART the app for the new key pair to take effect.", nil)];
        });
    });
}

#pragma mark - Actions

-(void)saveADBKey {
    NSLog(@"Saving ADB Key");
    
    NSError *saveError = nil;
    [self.keyTextView endEditing:YES];
    [self.pubkeyTextView endEditing:YES];
    
    if ([[self loadADBKey] isEqualToString:self.keyTextView.text] == NO) {
        [self.keyTextView.text writeToFile:[self adbKeyPath] atomically:YES encoding:NSUTF8StringEncoding error:&saveError];
    }
    
    if (saveError != nil) {
        [self showAlert:[NSString stringWithFormat:NSLocalizedString(@"Save [adbkey] ERROR: %@", nil), saveError]];
        return;
    }
    
    if ([[self loadADBPubKey] isEqualToString:self.pubkeyTextView.text] == NO) {
        [self.pubkeyTextView.text writeToFile:[self adbPubKeyPath] atomically:YES encoding:NSUTF8StringEncoding error:&saveError];
    }
    
    if (saveError != nil) {
        [self showAlert:[NSString stringWithFormat:NSLocalizedString(@"Save [adbkey.pub] ERROR: %@", nil), saveError]];
        return;
    }
    
    MBProgressHUD *hudView = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hudView.mode = MBProgressHUDModeText;
    hudView.label.text = NSLocalizedString(@"ADB Key Pairs Saved", nil);
    hudView.label.numberOfLines = 2;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [hudView hideAnimated:YES];
    });
}

-(void)generateADBKeyPair {
    NSLog(@"Generating New ADB Key");
    
    UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"Scrcpy Remote" message:NSLocalizedString(@"Please note that after regenerating the ADB key pairs, you may need to RE-AUTHORIZE on your remote phone.", nil) preferredStyle:(UIAlertControllerStyleAlert)];
    [confirmAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes, Continue", nil) style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        [self generateNewADBKey];
    }]];
    [confirmAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No, Stop Generate", nil) style:(UIAlertActionStyleCancel) handler:nil]];
    [self presentViewController:confirmAlert animated:YES completion:nil];
}

-(void)cancel {
    NSLog(@"Cancel and Exit ADB Key Page");
    
    // Check if the key has been modified
    if ([[self loadADBKey] isEqualToString:self.keyTextView.text]) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    
    // ADB Key Changed, Confirm to Exit
    UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"Scrcpy Remote" message:NSLocalizedString(@"ADB Key has been modified but not saved, do you confirm to exit?", nil) preferredStyle:(UIAlertControllerStyleAlert)];
    __weak typeof(self) weak_self = self;
    [confirmAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        [weak_self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [confirmAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:(UIAlertActionStyleCancel) handler:nil]];
    
    [self presentViewController:confirmAlert animated:YES completion:nil];
}

-(void)endEditing {
    [self.keyTextView endEditing:YES];
    [self.pubkeyTextView endEditing:YES];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray <NSURL *>*)urls {
    NSLog(@"Picked URLs: %@", urls);
    MBProgressHUD *tipsView = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    tipsView.mode = MBProgressHUDModeText;
    tipsView.label.text = NSLocalizedString(@"ADB Key Pairs Exported", nil);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [tipsView hideAnimated:YES];
    });
}

@end
