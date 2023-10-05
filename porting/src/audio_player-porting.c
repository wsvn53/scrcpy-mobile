//
//  audio_player-porting.c
//  scrcpy-module
//
//  Created by Ethan on 2023/5/21.
//
#include <AudioToolbox/AudioToolbox.h>
#include <AudioUnit/AudioUnit.h>

#define swr_convert(...)        swr_convert_hijack(__VA_ARGS__)

#include "audio_player.c"

#undef swr_convert

int swr_convert(struct SwrContext *s, uint8_t **out, int out_count,
                                const uint8_t **in , int in_count);
int swr_convert_hijack(struct SwrContext *s, uint8_t **out, int out_count,
                const uint8_t **in , int in_count) {
    // TODO: resample audio with accelerated API
    return swr_convert(s, out, out_count, in, in_count);
}

