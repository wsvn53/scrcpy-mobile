//
//  video_buffer-porting.c
//  scrcpy-module
//
//  Created by Ethan on 2022/6/8.
//

#define sc_video_buffer_start(...)      sc_video_buffer_start_hijack(__VA_ARGS__)

#include "video_buffer.c"

#undef sc_video_buffer_start

bool
sc_video_buffer_start(struct sc_video_buffer *vb) {
    // To reset vb->b.stopped to false for reconnecting
    // Otherwise, the screen cannot be updated after reconnect again
    vb->b.stopped = false;
    
    sc_video_buffer_start_hijack(vb);
}
