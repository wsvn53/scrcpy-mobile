//
//  ADBClient.h
//  Scrcpy Remote
//
//  Created by Ethan on 12/16/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Status Enum
typedef NS_ENUM(NSInteger, ADBDeviceStatus) {
    ADBDeviceStatusUnknown = 0,
    ADBDeviceStatusDevice,
    ADBDeviceStatusOffline,
    ADBDeviceStatusUnauthorized,
    ADBDeviceStatusRecovery,
    ADBDeviceStatusBootloader
};

// Execute ADB Command Callback
typedef void (^ADBClientCallback)(NSString * _Nullable output, int returnCode);

@interface ADBDevice : NSObject

@property (nonatomic, copy) NSString *serial;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, assign) ADBDeviceStatus status;

- (instancetype)initWith:(NSString *)deviceLine;

@end

@interface ADBClient : NSObject

@property (nonatomic, strong, readonly) NSArray <ADBDevice *> *adbDevices;
@property (nonatomic, assign, readonly) BOOL isADBLaunched;
@property (nonatomic, assign, readonly) int listenPort;
@property (atomic, copy, nullable) NSString *activeScrcpySerial;

/// Send numeric PIN key events without logging the command or its output.
- (void)sendPIN:(NSString *)pin onDevice:(NSString *)serial callback:(ADBClientCallback)callback;

+ (instancetype)shared;

// Execute ADB Command sync
- (NSString *)executeADBCommand:(NSArray <NSString *>*)commands returnCode:(int * __nullable)returnCode;

// Execute ADB Command Async
- (void)executeADBCommandAsync:(NSArray<NSString *> *)commands callback:(ADBClientCallback)callback;

// ADB Key Management Methods
- (NSString *)getADBHomeDirectory;
- (NSString *)getADBAndroidDirectory;
- (NSString *)readADBPrivateKey;
- (NSString *)readADBPublicKey;
- (BOOL)writeADBPrivateKey:(NSString *)privateKey;
- (BOOL)writeADBPublicKey:(NSString *)publicKey;
- (BOOL)generateNewADBKeyPair;
- (BOOL)exportADBKeysToDirectory:(NSString *)directoryPath;
- (BOOL)importADBKeysFromDirectory:(NSString *)directoryPath;
- (BOOL)adbKeyPairExists;

@end

// MARK: - ADBClient Action Execution Extension

@interface ADBClient (ActionExecution)

/// 执行 ADB Home 按键
/// @param deviceSerial 目标设备序列号
/// @param completion 完成回调
- (void)executeHomeKeyOnDevice:(NSString *)deviceSerial completion:(ADBClientCallback)completion;

/// 执行 ADB Switch 按键（App Switch/Recent Apps）
/// @param deviceSerial 目标设备序列号
/// @param completion 完成回调
- (void)executeSwitchKeyOnDevice:(NSString *)deviceSerial completion:(ADBClientCallback)completion;

/// 执行 ADB 按键序列
/// @param keyCodes 按键码数组
/// @param deviceSerial 目标设备序列号
/// @param intervalMs 按键间隔（毫秒）
/// @param completion 完成回调
- (void)executeKeySequence:(NSArray<NSNumber *> *)keyCodes
                  onDevice:(NSString *)deviceSerial
                  interval:(NSInteger)intervalMs
                completion:(void(^)(NSInteger successCount, NSString *error))completion;

/// 执行 ADB Shell 命令序列
/// @param commands 命令字符串数组
/// @param deviceSerial 目标设备序列号
/// @param intervalMs 命令间隔（毫秒）
/// @param completion 完成回调
- (void)executeShellCommands:(NSArray<NSString *> *)commands
                    onDevice:(NSString *)deviceSerial
                    interval:(NSInteger)intervalMs
                  completion:(void(^)(BOOL success, NSString *error))completion;

@end

NS_ASSUME_NONNULL_END
