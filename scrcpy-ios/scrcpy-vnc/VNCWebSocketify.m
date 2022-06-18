//
//  VNCWebSocketify.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/17.
//

#import "VNCWebSocketify.h"
#import "VNCUpstreamSocket.h"

@interface VNCWebSocketify ()
@property (nonatomic, strong)   VNCUpstreamSocket  *upstreamSocket;

@end

@implementation VNCWebSocketify

- (void)didOpen {
    [super didOpen];
    NSLog(@"-> WebSocket didOpen");
    [self connectUpstream:@"mini.wsen.me" port:5900];
}

- (void)didReceiveMessage:(NSString *)msg {
    NSLog(@"-> WebSocket: %@", msg);
    NSData *data = [msg dataUsingEncoding:(NSUTF8StringEncoding)];
    [self.upstreamSocket writeData:data];
}

- (void)didClose {
    [super didClose];
    [self.upstreamSocket disconnect];
    NSLog(@"-> WebSocket didClose");
}

#pragma mark - Upstream

-(void)connectUpstream:(NSString *)host port:(NSInteger)port {
    NSLog(@"-> Connect Upstream: %@:%@", host, @(port));
    self.upstreamSocket = [[VNCUpstreamSocket alloc] init];
    __weak typeof(self) _self = self;
    self.upstreamSocket.onUpstreamSocketRead = ^(NSData *data) {
        [_self sendData:data];
        NSLog(@"-> WebSocket: didSendData");
    };
    [self.upstreamSocket connectUpstream:host port:port];
}

@end
