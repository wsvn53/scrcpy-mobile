//
//  VNCUpstreamSocket.m
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/17.
//

#import "VNCUpstreamSocket.h"
#import "GCDAsyncSocket.h"

@interface VNCUpstreamSocket ()
@property (nonatomic, strong)   GCDAsyncSocket  *upstreamSocket;
@end

@implementation VNCUpstreamSocket

-(void)connectUpstream:(NSString *)host port:(NSInteger)port {
    self.upstreamSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_queue_create("upstream", 0)];
    NSError *error = nil;
    [self.upstreamSocket connectToHost:host onPort:port withTimeout:30 error:&error];
    if (error != nil) { NSLog(@"ERROR: %@", error); }
}

-(void)disconnect {
    [self.upstreamSocket disconnect];
}

-(void)writeData:(NSData *)data {
    [self.upstreamSocket writeData:data withTimeout:-1 tag:0];
}

#pragma mark - GCDAsyncSocketDelegate

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    NSLog(@"-> Upstream: didConnectToHost");
    [self.upstreamSocket readDataWithTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    NSLog(@"-> Upstream: didReadData %@ - tag: %ld", data, tag);
    if (self.onUpstreamSocketRead) {
        self.onUpstreamSocketRead(data);
    }
    [self.upstreamSocket readDataWithTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    NSLog(@"-> Upstream: didWriteData - tag: %ld", tag);
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    NSLog(@"-> Upstream: didDisconnect - %@", err);
}

@end
