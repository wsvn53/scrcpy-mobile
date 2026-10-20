#ifndef SCRCPY_PIN_INPUT_H
#define SCRCPY_PIN_INPUT_H

#import <Foundation/Foundation.h>

// Keep validation shared by the dialog and the ADB command builder.
static inline BOOL ScrcpyIsValidPIN(NSString *pin) {
    if (pin.length < 4 || pin.length > 16) { return NO; }
    NSCharacterSet *nonDigits = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    return [pin rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

static inline NSArray<NSString *> *ScrcpyPINArguments(NSString *pin, NSString *serial) {
    if (!ScrcpyIsValidPIN(pin) || !serial.length) { return nil; }
    NSMutableString *command = [NSMutableString stringWithString:
        @"input keyevent 224; input keyevent 82; sleep 0.3; input keyevent"];
    // Remove an incomplete PIN before sending a new one. Never retry a submission.
    for (NSUInteger i = 0; i < 16; i++) { [command appendString:@" 67"]; }
    for (NSUInteger i = 0; i < pin.length; i++) {
        [command appendFormat:@" %d", 7 + [pin characterAtIndex:i] - '0'];
    }
    [command appendString:@" 66"];
    return @[@"-s", serial, @"shell", command];
}

#endif
