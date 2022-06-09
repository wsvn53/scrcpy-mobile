//
//  decoder-porting.c
//  scrcpy-module
//
//  Created by Ethan on 2022/6/8.
//

#define avcodec_alloc_context3(...)     avcodec_alloc_context3_fix(__VA_ARGS__)

#include "decoder.c"

#undef avcodec_alloc_context3

__attribute__((weak))
bool avcodec_enable_hardware_decoding(void) {
    return true;
}

AVCodecContext *avcodec_alloc_context3(const AVCodec *codec);
AVCodecContext *avcodec_alloc_context3_fix(const AVCodec *codec) {
    AVCodecContext *context = avcodec_alloc_context3(codec);
    
    if (avcodec_enable_hardware_decoding() == false) {
        printf("hardware decoding is disabled\n");
        return context;
    }
    
    // Create context with hardware decoder
    AVBufferRef *codec_buf;
    const char *codecName = av_hwdevice_get_type_name(AV_HWDEVICE_TYPE_VIDEOTOOLBOX);
    enum AVHWDeviceType type = av_hwdevice_find_type_by_name(codecName);
    int ret = av_hwdevice_ctx_create(&codec_buf, type, NULL, NULL, 0);
    if (ret == 0) {
        context->hw_device_ctx = av_buffer_ref(codec_buf);
        return context;
    }
    
    printf("[WARN] Init hardware decoder FAILED, fallback to foftware decoder.");
    return context;
}
