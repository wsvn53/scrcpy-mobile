//
//  VNCHTTPConnection.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/15.
//

#import "VNCHTTPConnection.h"
#import "HTTPFileResponse.h"
#import "VNCWebSocketify.h"

@implementation VNCHTTPConnection

-(WebSocket *)webSocketForURI:(NSString *)path {
    if ([path hasSuffix:@"/websockify"]) {
        return [[VNCWebSocketify alloc] initWithRequest:request socket:asyncSocket];
    }
    return [super webSocketForURI:path];
}

@end
