//
//  ADBClient.m
//  Scrcpy Remote
//
//  Created by Ethan on 12/16/24.
//

#import "ADBClient.h"
#import "PINInput.h"
#import "adb_public.h"
#import <sys/socket.h>
#import <netinet/in.h>

// C++-exception-safe wrapper around adb_commandline_porting. Defined in
// porting/src/adb-safe-porting.cpp; catches std::system_error from
// std::thread::join() inside adb_server_cleanup → kick_all_transports →
// ReconnectHandler::Stop so a failed worker join no longer SIGABRTs the app.
extern int adb_commandline_porting_safe(char **output_buffer,
                                         size_t *output_buffer_size,
                                         int argc,
                                         const char **argv);

#define kADBConnectStatusUpdated    @"ADBConnectStatusUpdated"

void adb_connect_status_updated(const char *serial, const char *status)
{
    NSLog(@"ADB Connect status updated: %s, %s", serial, status);
    // Post Notification
    [[NSNotificationCenter defaultCenter] postNotificationName:kADBConnectStatusUpdated object:nil userInfo:@{
        @"serial": [NSString stringWithUTF8String:serial],
        @"status": [NSString stringWithUTF8String:status]
    }];
}

@implementation ADBDevice

- (instancetype)initWith:(NSString *)deviceLine
{
    self = [super init];
    if (self) {
        // Skip "List of devices attached"
        if ([deviceLine.lowercaseString isEqualToString:@"list of devices attached"]) { return nil; }
        // Device line format: "19071FDA600789    device"
        NSArray <NSString *> *components = [deviceLine componentsSeparatedByString:@"\t"];
        if (components.count != 2) { return nil; }
        self.serial = components[0];
        self.statusText = components[1];
    }
    return self;
}

- (void)setStatusText:(NSString *)statusText
{
    _statusText = statusText;
    _status = [self.class statusFromText:statusText];
}

+ (ADBDeviceStatus)statusFromText:(NSString *)text
{
    if ([text isEqualToString:@"device"]) {
        return ADBDeviceStatusDevice;
    }
    if ([text isEqualToString:@"offline"]) {
        return ADBDeviceStatusOffline;
    }
    if ([text isEqualToString:@"unauthorized"]) {
        return ADBDeviceStatusUnauthorized;
    }
    if ([text isEqualToString:@"recovery"]) {
        return ADBDeviceStatusRecovery;
    }
    if ([text isEqualToString:@"bootloader"]) {
        return ADBDeviceStatusBootloader;
    }
    return ADBDeviceStatusUnknown;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@: %@, %@", [super description], self.serial, self.statusText];
}

@end

@interface ADBClient ()

@property (nonatomic, strong)   NSMutableArray <ADBDevice *> *devicesInternal;

@end

@implementation ADBClient

+ (instancetype)shared
{
    static ADBClient *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ADBClient alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) { [self setup]; }
    return self;
}

- (void)setup
{
    // Time to profile adb start up
    NSDate *start = [NSDate date];
    
    // Observe Notifaction
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(adbConnectStatusUpdated:)
                                                 name:kADBConnectStatusUpdated
                                               object:nil];
    
    // Enable verbose trace
    // adb_enable_trace();

    // Find an available port in range [15037, 15037 + 32]
    NSLog(@"Find an available port in range [15037, 15037 + 32]");
    for (int i = 0; i < 32; i++) {
        int port = 25037 + i;
        // Try bind on port by sockect func to test if it's available
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_ANY);
        addr.sin_port = htons(port);
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) {
            NSLog(@"Check socket failed on port: %d, errno: %d", port, errno);
            continue;
        }
        if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            NSLog(@"Check bind failed on port: %d, errno: %d", port, errno);
            close(fd);
            continue;
        }
        close(fd);
        adb_set_server_port([NSString stringWithFormat:@"%d", port].UTF8String);
        _listenPort = port;
        NSLog(@"ADB Client port set to port: %d", port);
        break;
    }

    // Setup ADB home directory
    [self setupADBHomeDirectory];

    int returnCode = -1;
    NSString *output = [self executeADBCommandUnderlying:@[@"devices"] returnCode:&returnCode];
    if (returnCode != 0) {
        // Setup adb failed
        NSLog(@"❌ ADB Client setup failed: test `adb devices` command failed!");
        return;
    }
    NSLog(@"ADB Client setup success, output: %@", output);
    
    // Mark as launched
    _isADBLaunched = YES;

    // Time to profile adb start up
    NSDate *end = [NSDate date];
    NSLog(@"ADB Client setup time: %f", [end timeIntervalSinceDate:start]);
}

- (void)setupADBHomeDirectory
{
    NSString *adbHome = [self getADBHomeDirectory];
    adb_set_home(adbHome.UTF8String);
    NSLog(@"ADB home directory set to: %@", adbHome);
}

- (NSString *)executeADBCommandUnderlying:(NSArray <NSString *>*)commands returnCode:(int*)returnCode
{
    return [self executeADBCommandUnderlying:commands returnCode:returnCode logCommand:YES];
}

- (NSString *)executeADBCommandUnderlying:(NSArray<NSString *> *)commands
                             returnCode:(int *)returnCode
                             logCommand:(BOOL)logCommand
{
    char *output = NULL;
    size_t output_size = 0;
    // Convert NSArray to char**
    const char **argv = malloc(sizeof(char *) * commands.count);
    for (int i = 0; i < commands.count; i++) {
        argv[i] = [NSString stringWithFormat:@"%@", commands[i]].UTF8String;
    }
    int ret = adb_commandline_porting_safe(&output, &output_size, (int)commands.count, argv);
    if (returnCode) { *returnCode = ret; }
    if (logCommand) {
        NSLog(@"> adb_commandline_porting [%@]\n> return code: %d\n> output text:\n%s",
              [commands componentsJoinedByString:@" "], ret, output);
    }
    
    // Special for connect and disconnect commands, we need to update devices after executed
    if (commands.count > 0 && [@[@"connect", @"disconnect"] containsObject:commands[0]]) {
        [self updateDevices];
    }
    
    NSString *result = output_size > 0 && output != NULL ? [NSString stringWithUTF8String:output] : @"";
    free(argv);
    free(output);
    return result;
}

- (NSString *)executeADBCommand:(NSArray <NSString *>*)commands returnCode:(int * __nullable)returnCode
{
    if (!_isADBLaunched) {
        NSLog(@"❌ ADB Client not launched yet!");
        if (returnCode) { *returnCode = -1; }
        return nil;
    }
    return [self executeADBCommandUnderlying:commands returnCode:returnCode];
}

- (void)executeADBCommandAsync:(NSArray<NSString *> *)commands callback:(ADBClientCallback)callback
{
    if (!_isADBLaunched) {
        NSLog(@"❌ ADB Client not launched yet!");
        if (callback) { callback(nil, -1); }
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        int returnCode = -1;
        NSString *output = [self executeADBCommand:commands returnCode:&returnCode];
        if (callback) { callback(output, returnCode); }
    });
}

- (void)sendPIN:(NSString *)pin onDevice:(NSString *)serial callback:(ADBClientCallback)callback {
    NSArray *arguments = ScrcpyPINArguments(pin, serial);
    if (!self.isADBLaunched || !arguments) {
        if (callback) { callback(nil, -1); }
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if (![serial isEqualToString:self.activeScrcpySerial]) {
            if (callback) { callback(nil, -1); }
            return;
        }
        int code = -1;
        [self executeADBCommandUnderlying:arguments returnCode:&code logCommand:NO];
        if (callback) { callback(nil, code); }
    });
}

#pragma mark - Getter & Setter

- (NSArray<ADBDevice *> *)adbDevices
{
    return [self.devicesInternal copy];
}

- (NSMutableArray<ADBDevice *> *)devicesInternal
{
    if (!_devicesInternal) {
        _devicesInternal = [NSMutableArray array];
    }
    return _devicesInternal;
}

#pragma mark - ADB Key Management

- (NSString *)getADBHomeDirectory
{
    NSArray <NSString *> *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return documentPaths.lastObject;
}

- (NSString *)getADBAndroidDirectory
{
    NSString *adbHome = [self getADBHomeDirectory];
    return [adbHome stringByAppendingPathComponent:@".android"];
}

- (BOOL)ensureADBAndroidDirectoryExists
{
    NSString *androidDir = [self getADBAndroidDirectory];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:androidDir]) {
        NSError *error;
        BOOL success = [fileManager createDirectoryAtPath:androidDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
        if (!success) {
            NSLog(@"Error creating .android directory: %@", error.localizedDescription);
            return NO;
        }
        NSLog(@"Created .android directory at: %@", androidDir);
    }
    return YES;
}

- (NSString *)readADBPrivateKey
{
    NSString *keyPath = [[self getADBAndroidDirectory] stringByAppendingPathComponent:@"adbkey"];
    NSError *error;
    NSString *content = [NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"Error reading ADB private key: %@", error.localizedDescription);
        return nil;
    }
    return content;
}

- (NSString *)readADBPublicKey
{
    NSString *keyPath = [[self getADBAndroidDirectory] stringByAppendingPathComponent:@"adbkey.pub"];
    NSError *error;
    NSString *content = [NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"Error reading ADB public key: %@", error.localizedDescription);
        return nil;
    }
    return content;
}

- (BOOL)writeADBPrivateKey:(NSString *)privateKey
{
    if (!privateKey || privateKey.length == 0) {
        NSLog(@"Error: Private key content is empty");
        return NO;
    }
    
    // Ensure .android directory exists
    if (![self ensureADBAndroidDirectoryExists]) {
        return NO;
    }
    
    NSString *keyPath = [[self getADBAndroidDirectory] stringByAppendingPathComponent:@"adbkey"];
    NSError *error;
    BOOL success = [privateKey writeToFile:keyPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!success) {
        NSLog(@"Error writing ADB private key: %@", error.localizedDescription);
        return NO;
    }
    
    // Set proper file permissions (0600 - read/write for owner only)
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = @{NSFilePosixPermissions: @(0600)};
    [fileManager setAttributes:attributes ofItemAtPath:keyPath error:&error];
    if (error) {
        NSLog(@"Warning: Could not set file permissions for private key: %@", error.localizedDescription);
    }
    
    NSLog(@"ADB private key saved successfully to: %@", keyPath);
    return YES;
}

- (BOOL)writeADBPublicKey:(NSString *)publicKey
{
    if (!publicKey || publicKey.length == 0) {
        NSLog(@"Error: Public key content is empty");
        return NO;
    }
    
    // Ensure .android directory exists
    if (![self ensureADBAndroidDirectoryExists]) {
        return NO;
    }
    
    NSString *keyPath = [[self getADBAndroidDirectory] stringByAppendingPathComponent:@"adbkey.pub"];
    NSError *error;
    BOOL success = [publicKey writeToFile:keyPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!success) {
        NSLog(@"Error writing ADB public key: %@", error.localizedDescription);
        return NO;
    }
    
    // Set proper file permissions (0644 - read/write for owner, read for others)
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = @{NSFilePosixPermissions: @(0644)};
    [fileManager setAttributes:attributes ofItemAtPath:keyPath error:&error];
    if (error) {
        NSLog(@"Warning: Could not set file permissions for public key: %@", error.localizedDescription);
    }
    
    NSLog(@"ADB public key saved successfully to: %@", keyPath);
    return YES;
}

- (BOOL)generateNewADBKeyPair
{
    // Ensure .android directory exists before generating keys
    if (![self ensureADBAndroidDirectoryExists]) {
        return NO;
    }
    
    // Execute ADB keygen command to generate new key pair
    // The keygen command should create keys in the .android subdirectory
    NSString *androidDir = [self getADBAndroidDirectory];
    int returnCode = -1;
    NSString *output = [self executeADBCommandUnderlying:@[@"keygen", [androidDir stringByAppendingString:@"/adbkey"]] returnCode:&returnCode];
    
    if (returnCode == 0) {
        NSLog(@"ADB key pair generated successfully: %@", output);
        return YES;
    } else {
        NSLog(@"Failed to generate ADB key pair. Return code: %d, Output: %@", returnCode, output);
        return NO;
    }
}

- (BOOL)exportADBKeysToDirectory:(NSString *)directoryPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    
    // Ensure destination directory exists
    if (![fileManager fileExistsAtPath:directoryPath]) {
        BOOL created = [fileManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:&error];
        if (!created) {
            NSLog(@"Error creating export directory: %@", error.localizedDescription);
            return NO;
        }
    }
    
    NSString *androidDir = [self getADBAndroidDirectory];
    NSString *privateKeySource = [androidDir stringByAppendingPathComponent:@"adbkey"];
    NSString *publicKeySource = [androidDir stringByAppendingPathComponent:@"adbkey.pub"];
    
    NSString *privateKeyDest = [directoryPath stringByAppendingPathComponent:@"adbkey"];
    NSString *publicKeyDest = [directoryPath stringByAppendingPathComponent:@"adbkey.pub"];
    
    // Export private key
    if ([fileManager fileExistsAtPath:privateKeySource]) {
        BOOL success = [fileManager copyItemAtPath:privateKeySource toPath:privateKeyDest error:&error];
        if (!success) {
            NSLog(@"Error exporting private key: %@", error.localizedDescription);
            return NO;
        }
    } else {
        NSLog(@"Private key file does not exist at: %@", privateKeySource);
        return NO;
    }
    
    // Export public key
    if ([fileManager fileExistsAtPath:publicKeySource]) {
        BOOL success = [fileManager copyItemAtPath:publicKeySource toPath:publicKeyDest error:&error];
        if (!success) {
            NSLog(@"Error exporting public key: %@", error.localizedDescription);
            return NO;
        }
    } else {
        NSLog(@"Public key file does not exist at: %@", publicKeySource);
        return NO;
    }
    
    NSLog(@"ADB keys exported successfully to: %@", directoryPath);
    return YES;
}

- (BOOL)importADBKeysFromDirectory:(NSString *)directoryPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;

    NSString *privateKeySource = [directoryPath stringByAppendingPathComponent:@"adbkey"];
    NSString *publicKeySource = [directoryPath stringByAppendingPathComponent:@"adbkey.pub"];

    // Check if both key files exist in source directory
    if (![fileManager fileExistsAtPath:privateKeySource]) {
        NSLog(@"Private key file does not exist at: %@", privateKeySource);
        return NO;
    }

    if (![fileManager fileExistsAtPath:publicKeySource]) {
        NSLog(@"Public key file does not exist at: %@", publicKeySource);
        return NO;
    }

    // Ensure .android directory exists
    if (![self ensureADBAndroidDirectoryExists]) {
        return NO;
    }

    NSString *androidDir = [self getADBAndroidDirectory];
    NSString *privateKeyDest = [androidDir stringByAppendingPathComponent:@"adbkey"];
    NSString *publicKeyDest = [androidDir stringByAppendingPathComponent:@"adbkey.pub"];

    // Remove existing keys if present
    if ([fileManager fileExistsAtPath:privateKeyDest]) {
        [fileManager removeItemAtPath:privateKeyDest error:&error];
        if (error) {
            NSLog(@"Error removing existing private key: %@", error.localizedDescription);
            return NO;
        }
    }

    if ([fileManager fileExistsAtPath:publicKeyDest]) {
        [fileManager removeItemAtPath:publicKeyDest error:&error];
        if (error) {
            NSLog(@"Error removing existing public key: %@", error.localizedDescription);
            return NO;
        }
    }

    // Import private key
    BOOL success = [fileManager copyItemAtPath:privateKeySource toPath:privateKeyDest error:&error];
    if (!success) {
        NSLog(@"Error importing private key: %@", error.localizedDescription);
        return NO;
    }

    // Set proper file permissions for private key (0600 - read/write for owner only)
    NSDictionary *privateKeyAttributes = @{NSFilePosixPermissions: @(0600)};
    [fileManager setAttributes:privateKeyAttributes ofItemAtPath:privateKeyDest error:&error];
    if (error) {
        NSLog(@"Warning: Could not set file permissions for private key: %@", error.localizedDescription);
    }

    // Import public key
    success = [fileManager copyItemAtPath:publicKeySource toPath:publicKeyDest error:&error];
    if (!success) {
        NSLog(@"Error importing public key: %@", error.localizedDescription);
        // Clean up private key since import failed
        [fileManager removeItemAtPath:privateKeyDest error:nil];
        return NO;
    }

    // Set proper file permissions for public key (0644 - read/write for owner, read for others)
    NSDictionary *publicKeyAttributes = @{NSFilePosixPermissions: @(0644)};
    [fileManager setAttributes:publicKeyAttributes ofItemAtPath:publicKeyDest error:&error];
    if (error) {
        NSLog(@"Warning: Could not set file permissions for public key: %@", error.localizedDescription);
    }

    NSLog(@"ADB keys imported successfully from: %@", directoryPath);
    return YES;
}

- (BOOL)adbKeyPairExists
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *androidDir = [self getADBAndroidDirectory];
    NSString *privateKeyPath = [androidDir stringByAppendingPathComponent:@"adbkey"];
    NSString *publicKeyPath = [androidDir stringByAppendingPathComponent:@"adbkey.pub"];

    return [fileManager fileExistsAtPath:privateKeyPath] && [fileManager fileExistsAtPath:publicKeyPath];
}

#pragma mark - Utils

- (void)updateDevices
{
    int returnCode = -1;
    NSString *output = [self executeADBCommand:@[@"devices"] returnCode:&returnCode];
    if (returnCode != 0) {
        NSLog(@"❌ ADB Client update devices failed: test `adb devices` command failed!");
        return;
    }
    
    // Parse devices
    NSArray <NSString *> *lines = [output componentsSeparatedByString:@"\n"];
    for (int i = 1; i < lines.count; i++) {
        ADBDevice *device = [[ADBDevice alloc] initWith:lines[i]];
        if (device == nil) { continue; }
        
        // Check if device is in our list, just update status
        // To avoid other object reference this object not updated
        ADBDevice *foundDevice = [self findDevice:device.serial];
        if (foundDevice) {
            foundDevice.statusText = device.statusText;
        } else {
            [self.devicesInternal addObject:device];
        }
    }
}

- (ADBDevice *)findDevice:(NSString *)serial
{
    for (ADBDevice *device in self.devicesInternal) {
        if ([device.serial isEqualToString:serial]) {
            return device;
        }
    }
    return nil;
}

#pragma mark - Notification

- (void)adbConnectStatusUpdated:(NSNotification *)notification
{
    NSDictionary *userInfo = notification.userInfo;
    NSString *serial = userInfo[@"serial"];
    NSString *status = userInfo[@"status"];
    NSLog(@"💬 ADB Connect status updated: %@, %@", serial, status);
    
    // Update connected devices
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateDevices]; });
}

@end

#pragma mark - Action Execution

@implementation ADBClient (ActionExecution)

- (void)executeHomeKeyOnDevice:(NSString *)deviceSerial completion:(ADBClientCallback)completion {
    NSLog(@"🏠 [ADBClient] Executing home key on device: %@", deviceSerial);
    
    NSArray *command = @[@"-s", deviceSerial, @"shell", @"input", @"keyevent", @"KEYCODE_HOME"];
    
    [self executeADBCommandAsync:command callback:^(NSString *output, int returnCode) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (returnCode == 0) {
                NSLog(@"✅ [ADBClient] Home key executed successfully on device: %@", deviceSerial);
            } else {
                NSLog(@"❌ [ADBClient] Home key failed on device %@: %@", deviceSerial, output ?: @"Unknown error");
            }
            if (completion) completion(output, returnCode);
        });
    }];
}

- (void)executeSwitchKeyOnDevice:(NSString *)deviceSerial completion:(ADBClientCallback)completion {
    NSLog(@"🔄 [ADBClient] Executing switch key on device: %@", deviceSerial);
    
    NSArray *command = @[@"-s", deviceSerial, @"shell", @"input", @"keyevent", @"KEYCODE_APP_SWITCH"];
    
    [self executeADBCommandAsync:command callback:^(NSString *output, int returnCode) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (returnCode == 0) {
                NSLog(@"✅ [ADBClient] Switch key executed successfully on device: %@", deviceSerial);
            } else {
                NSLog(@"❌ [ADBClient] Switch key failed on device %@: %@", deviceSerial, output ?: @"Unknown error");
            }
            if (completion) completion(output, returnCode);
        });
    }];
}

- (void)executeKeySequence:(NSArray<NSNumber *> *)keys onDevice:(NSString *)deviceSerial interval:(NSInteger)interval completion:(void (^)(NSInteger successCount, NSString *error))completion {
    NSLog(@"⌨️ [ADBClient] Executing key sequence on device: %@ with %lu keys", deviceSerial, (unsigned long)keys.count);
    
    if (keys.count == 0) {
        if (completion) completion(0, nil);
        return;
    }
    
    // 保存 weak reference 避免 retain cycle
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) completion(0, @"ADBClient instance deallocated");
            return;
        }
        
        NSInteger successCount = 0;
        NSString *lastError = nil;
        
        for (NSUInteger i = 0; i < keys.count; i++) {
            NSString *key = [keys[i] stringValue];
            NSArray *command = @[@"-s", deviceSerial, @"shell", @"input", @"keyevent", key];
            
            int returnCode = -1;
            NSString *output = [strongSelf executeADBCommand:command returnCode:&returnCode];
            
            if (returnCode == 0) {
                successCount++;
            } else {
                lastError = [NSString stringWithFormat:@"Key input failed on device %@: %@", deviceSerial, output ?: @"Unknown error"];
                NSLog(@"❌ [ADBClient] Key %@ failed, continuing with remaining keys", key);
            }
            
            if (i < keys.count - 1 && interval > 0) {
                [NSThread sleepForTimeInterval:interval / 1000.0];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (successCount == keys.count) {
                NSLog(@"✅ [ADBClient] Key sequence executed successfully on device: %@ (%ld/%lu keys)", deviceSerial, (long)successCount, (unsigned long)keys.count);
            } else {
                NSLog(@"❌ [ADBClient] Key sequence partially failed on device: %@ (%ld/%lu keys succeeded). Last error: %@", deviceSerial, (long)successCount, (unsigned long)keys.count, lastError);
            }
            if (completion) completion(successCount, lastError);
        });
    });
}

- (void)executeShellCommands:(NSArray<NSString *> *)commands onDevice:(NSString *)deviceSerial interval:(NSInteger)interval completion:(void (^)(BOOL success, NSString *error))completion {
    NSLog(@"🔧 [ADBClient] Executing shell commands on device: %@ with %lu commands", deviceSerial, (unsigned long)commands.count);
    
    if (commands.count == 0) {
        if (completion) completion(YES, nil);
        return;
    }
    
    // 保存 weak reference 避免 retain cycle
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) completion(NO, @"ADBClient instance deallocated");
            return;
        }
        
        BOOL overallSuccess = YES;
        NSString *lastError = nil;
        
        for (NSUInteger i = 0; i < commands.count && overallSuccess; i++) {
            NSString *command = commands[i];
            NSMutableArray *fullCommand = [NSMutableArray arrayWithArray:@[@"-s", deviceSerial, @"shell"]];
            [fullCommand addObjectsFromArray:[command componentsSeparatedByString:@" "]];
            
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
            __block BOOL stepSuccess = YES;
            __block NSString *stepError = nil;
            
            [strongSelf executeADBCommandAsync:fullCommand callback:^(NSString *output, int returnCode) {
                if (returnCode != 0) {
                    stepSuccess = NO;
                    stepError = [NSString stringWithFormat:@"Shell command failed on device %@: %@", deviceSerial, output ?: @"Unknown error"];
                }
                dispatch_semaphore_signal(semaphore);
            }];
            
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            
            if (!stepSuccess) {
                overallSuccess = NO;
                lastError = stepError;
            }
            
            if (overallSuccess && i < commands.count - 1 && interval > 0) {
                [NSThread sleepForTimeInterval:interval / 1000.0];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (overallSuccess) {
                NSLog(@"✅ [ADBClient] Shell commands executed successfully on device: %@", deviceSerial);
            } else {
                NSLog(@"❌ [ADBClient] Shell commands failed: %@", lastError);
            }
            if (completion) completion(overallSuccess, lastError);
        });
    });
}

@end
