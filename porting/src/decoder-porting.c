//
//  decoder-porting.c
//  scrcpy-module
//
//  Created by Ethan on 2022/6/8.
//

#define avcodec_send_packet(...)        avcodec_send_packet_hijack(__VA_ARGS__)

#include "decoder.c"

#undef avcodec_send_packet

bool ScrcpyEnableHardwareDecoding(void);
int avcodec_send_packet(AVCodecContext *avctx, const AVPacket *avpkt);
int avcodec_send_packet_hijack(AVCodecContext *avctx, const AVPacket *avpkt) {
    int ret = avcodec_send_packet(avctx, avpkt);
    
    if (ret == AVERROR_UNKNOWN && ScrcpyEnableHardwareDecoding()) {
        // Fix Hardware Decoding Error After Return From Background
        return 0;
    }
    
    return ret;
}
