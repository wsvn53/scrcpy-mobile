// Run on macOS: xcrun clang -fobjc-arc -framework Foundation tests/pin-input.m -o /tmp/scrcpy-pin-tests && /tmp/scrcpy-pin-tests
#import <Foundation/Foundation.h>
#import "../scrcpy-app/ADBClient/PINInput.h"

int main(void) {
    @autoreleasepool {
        for (NSString *invalid in @[@"", @"123", @"12345678901234567", @"１２３４", @"١٢٣٤", @"12 34", @"1234\n", @"1234;id"]) {
            NSCAssert(!ScrcpyIsValidPIN(invalid), @"Reject invalid input");
            NSCAssert(ScrcpyPINArguments(invalid, @"test:5555") == nil, @"Do not construct commands for invalid input");
        }
        NSCAssert(!ScrcpyIsValidPIN(nil), @"Reject missing input");
        NSCAssert(ScrcpyIsValidPIN(@"0000"), @"Accept leading zeros");
        NSCAssert(ScrcpyIsValidPIN(@"1234567890123456"), @"Accept maximum length");
        NSCAssert(ScrcpyPINArguments(@"1234", @"") == nil, @"Require an explicit target");
        NSArray *args = ScrcpyPINArguments(@"0123456789", @"device with spaces;ignored");
        NSCAssert(args.count == 4 && [args[0] isEqual:@"-s"] && [args[1] isEqual:@"device with spaces;ignored"] && [args[2] isEqual:@"shell"], @"Target stays a separate argument");
        NSString *command = args[3];
        NSCAssert([command hasSuffix:@" 7 8 9 10 11 12 13 14 15 16 66"], @"Send numeric key events in order, then submit once");
        NSArray *parts = [command componentsSeparatedByString:@" "];
        NSUInteger deletes = 0;
        for (NSString *part in parts) { if ([part isEqual:@"67"]) { deletes++; } }
        NSCAssert(deletes == 16, @"Clear a partial PIN before typing");
        NSCAssert(![command containsString:@"0123456789"], @"Never send PIN as shell text");
        puts("PIN input checks passed");
    }
    return 0;
}
