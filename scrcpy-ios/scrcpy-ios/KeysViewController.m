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
#import "UICommonUtils.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

int adb_auth_key_generate(const char* filename);

@interface KeysViewController ()
@property (nonatomic, strong)   UITextView  *keyTextView;
@property (nonatomic, strong)   UITextView  *pubkeyTextView;
@end

@implementation KeysViewController

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
    self.title = NSLocalizedString(@"Import/Export ADB Keys", nil);
    
    // Setup appearance
    SetupViewControllerAppearance(self);

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Export", nil) 
                                                                              style:(UIBarButtonItemStylePlain)
                                                                             target:self
                                                                             action:@selector(onExportADBKey)];
    self.navigationItem.rightBarButtonItem.tintColor = DynamicTintColor();
    
    CVCreate.UIStackView(@[
        CVCreate.UIView.size(CGSizeMake(0, 5)),
        CVCreate.UILabel.boldFontSize(15)
            .text(NSLocalizedString(@"ADB Private Key(adbkey):", nil))
            .textColor(DynamicTextColor()),
        CVCreate.withView(self.keyTextView).fontSize(15)
            .size((CGSize){0, 200})
            .text([self loadADBKey])
            .cornerRadius(5.f)
            .backgroundColor(DynamicBackgroundColor())
            .textColor(DynamicTextColor())
            .border(UIColor.lightGrayColor, 1.f),
        CVCreate.UIView.size((CGSize){0, 1}),
        CVCreate.UILabel
            .boldFontSize(15)
            .text(NSLocalizedString(@"ADB Public Key(adbkey.pub):", nil))
            .textColor(DynamicTextColor()),
        CVCreate.withView(self.pubkeyTextView).fontSize(15)
            .size((CGSize){0, 200})
            .text([self loadADBPubKey])
            .cornerRadius(5.f)
            .backgroundColor(DynamicBackgroundColor())
            .textColor(DynamicTextColor())
            .border(DynamicTextFieldBorderColor(), 1.f),
        CreateDarkButton(NSLocalizedString(@"Save Privatekey & Pubkey", nil), self, @selector(onSaveADBKeyPair)),
        CreateLightButton(NSLocalizedString(@"Import ADB Key Pair From File", nil), self, @selector(onImportADBKeyPair)),
        CreateLightButton(NSLocalizedString(@"Generate New ADB Key Pair", nil), self, @selector(onGenerateADBKeyPair)),
        CreateLightButton(NSLocalizedString(@"Cancel", nil), self, @selector(cancel)),
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

#pragma mark - ADB Key Management

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
        ShowAlertFrom(self, [NSString stringWithFormat:NSLocalizedString(@"Load ADB Key Failed: %@", nil), error], nil, nil);
        return @"";
    }
    return adbKey;
}

-(NSString *)loadADBPubKey {
    NSError *error = nil;
    NSString *adbKey = [NSString stringWithContentsOfFile:[self adbPubKeyPath] encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        ShowAlertFrom(self, [NSString stringWithFormat:NSLocalizedString(@"Load ADB PubKey Failed: %@", nil), error], nil, nil);
        return @"";
    }
    return adbKey;
}

-(void)saveADBKey {
    NSError *saveError = nil;
    [self endEditing];
    
    if ([[self loadADBKey] isEqualToString:self.keyTextView.text] == NO) {
        [self.keyTextView.text writeToFile:[self adbKeyPath] atomically:YES encoding:NSUTF8StringEncoding error:&saveError];
    }
    
    if (saveError != nil) {
        ShowAlertFrom(self, [NSString stringWithFormat:NSLocalizedString(@"Save [adbkey] ERROR: %@", nil), saveError], nil, nil);
        return;
    }
    
    if ([[self loadADBPubKey] isEqualToString:self.pubkeyTextView.text] == NO) {
        [self.pubkeyTextView.text writeToFile:[self adbPubKeyPath] atomically:YES encoding:NSUTF8StringEncoding error:&saveError];
    }
    
    if (saveError != nil) {
        ShowAlertFrom(self, [NSString stringWithFormat:NSLocalizedString(@"Save [adbkey.pub] ERROR: %@", nil), saveError], nil, nil);
        return;
    }
    
    ShowAlertFrom(self, NSLocalizedString(@"ADB Key Pair Saved! Please restart app to take effect.", nil), nil, nil);
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
            ShowAlertFrom(weak_self, NSLocalizedString(@"New ADB key pair GENERATED.\nPlease RESTART the app for the new key pair to take effect.", nil), nil, nil);
        });
    });
}

-(void)importADBKeyFromFiless:(NSArray *)files {
    NSLog(@"Importing ADB Key Pair From Files: %@", files);
    for (NSURL *file in files) {
        BOOL isDir = NO;
        [NSFileManager.defaultManager fileExistsAtPath:file.path isDirectory:&isDir];
        if (isDir) {
            NSLog(@"-> Ignore, path %@ is directory", file.path);
            continue;
        }
        NSString *content = [NSString stringWithContentsOfFile:file.path encoding:NSUTF8StringEncoding error:nil];
        if ([content containsString:@"BEGIN PRIVATE KEY"]) {
            NSLog(@"-> Loading as adbkey: %@", file.path);
            self.keyTextView.text = content;
        }
        
        if ([file.pathExtension isEqualToString:@"pub"]) {
            NSLog(@"-> Loading as adbkey.pub: %@", file.path);
            self.pubkeyTextView.text = content;
        }
        
        [self saveADBKey];
    }
}

#pragma mark - Actions

-(void)onSaveADBKeyPair {
    NSLog(@"Saving ADB Key");
    [self saveADBKey];
}

-(void)onGenerateADBKeyPair {
    NSLog(@"Generating New ADB Key");
    
    ShowAlertFrom(self, NSLocalizedString(@"Please note that after regenerating the ADB key pair, you may need to RE-AUTHORIZE on your remote phone.", nil), [UIAlertAction actionWithTitle:NSLocalizedString(@"Yes, Continue", nil) style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        [self generateNewADBKey];
    }], [UIAlertAction actionWithTitle:NSLocalizedString(@"No, Stop Generate", nil) style:(UIAlertActionStyleCancel) handler:nil]);
}

-(void)cancel {
    NSLog(@"Cancel and Exit ADB Key Page");
    
    // Check if the key has been modified
    if ([[self loadADBKey] isEqualToString:self.keyTextView.text]) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    
    // ADB Key Changed, Confirm to Exit
    ShowAlertFrom(self, NSLocalizedString(@"ADB Key has been MODIFIED but not saved, do you confirm to exit?", nil), [UIAlertAction actionWithTitle:@"OK" style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }], [UIAlertAction actionWithTitle:@"Cancel" style:(UIAlertActionStyleCancel) handler:nil]);
}

-(void)endEditing {
    [self.keyTextView endEditing:YES];
    [self.pubkeyTextView endEditing:YES];
}

-(void)onExportADBKey {
    // Export ADB Key to Local File
    UIDocumentPickerViewController *pickerController = [[UIDocumentPickerViewController alloc] initWithURLs:@[
        [NSURL fileURLWithPath:[self adbKeyPath]],
        [NSURL fileURLWithPath:[self adbPubKeyPath]],
    ] inMode:(UIDocumentPickerModeExportToService)];
    pickerController.delegate = (id<UIDocumentPickerDelegate>)self;
    [self presentViewController:pickerController animated:YES completion:nil];
}

-(void)onImportADBKeyPair {
    NSLog(@"Importing ADB Key Pair");
    UIDocumentPickerViewController *importController = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[ @"public.item" ] inMode:(UIDocumentPickerModeImport)];
    importController.allowsMultipleSelection = YES;
    importController.delegate = (id<UIDocumentPickerDelegate>)self;
    [self presentViewController:importController animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray <NSURL *>*)urls {
    NSLog(@"Picked URLs: %@", urls);
    
    if (controller.documentPickerMode == UIDocumentPickerModeExportToService) {
        MBProgressHUD *tipsView = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        tipsView.mode = MBProgressHUDModeText;
        tipsView.label.text = NSLocalizedString(@"ADB Key Pair Exported", nil);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [tipsView hideAnimated:YES];
        });
    } else if (controller.documentPickerMode == UIDocumentPickerModeImport) {
        [self importADBKeyFromFiless:urls];
    }
}

@end
