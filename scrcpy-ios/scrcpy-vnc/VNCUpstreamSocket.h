//
//  VNCUpstreamSocket.h
//  scrcpy-ios
//
//  Created by Ethan on 2022/6/17.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VNCUpstreamSocket : NSObject

@property (nonatomic, copy) void(^onUpstreamSocketRead)(NSData *data);

-(void)connectUpstream:(NSString *)host port:(NSInteger)port;
-(void)disconnect;

-(void)writeData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
