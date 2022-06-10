//
//  screen-porting.c
//  scrcpy-module
//
//  Created by Ethan on 2022/6/3.
//

#include "stdbool.h"
#include <SDL2/SDL.h>
#include <SDL2/SDL_render.h>

bool avcodec_enable_hardware_decoding(void);
SDL_Texture * SDL_CreateTexture_hijack(SDL_Renderer * renderer,
                                       Uint32 format,
                                       int access, int w, int h);
int SDL_UpdateYUVTexture_hijack(SDL_Texture * texture,
                                const SDL_Rect * rect,
                                const Uint8 *Yplane, int Ypitch,
                                const Uint8 *Uplane, int Upitch,
                                const Uint8 *Vplane, int Vpitch);

#define sc_screen_init(...)   sc_screen_init_orig(__VA_ARGS__)
#define SDL_CreateTexture(...)   SDL_CreateTexture_hijack(__VA_ARGS__)
#define SDL_UpdateYUVTexture(...)   SDL_UpdateYUVTexture_hijack(__VA_ARGS__)
#define sc_video_buffer_consume(...)   sc_video_buffer_consume_hijack(__VA_ARGS__)

#include "screen.c"

#undef sc_screen_init
#undef SDL_CreateTexture
#undef SDL_UpdateYUVTexture
#undef sc_video_buffer_consume

struct sc_screen *
sc_screen_current_screen(struct sc_screen *screen) {
    static struct sc_screen *current_screen;
    if (screen != NULL) {
        current_screen = screen;
    }
    return current_screen;
}

__attribute__((weak))
float screen_scale(void) {
    return 2.f;
}

bool
sc_screen_init(struct sc_screen *screen,
               const struct sc_screen_params *params) {
    bool ret = sc_screen_init_orig(screen, params);

    // Set renderer scale
    SDL_RenderSetScale(screen->renderer, screen_scale(), screen_scale());
    
    // Save current screen pointer
    sc_screen_current_screen(screen);

    return ret;
}

__attribute__((weak))
void convert_to_metal_frame(AVFrame *frame) {}

// Hijack SDL_CreateTexture to enable render hardware decoded frame
SDL_Texture * SDL_CreateTexture_hijack(SDL_Renderer * renderer,
                                                        Uint32 format,
                                                        int access, int w,
                                                        int h)
{
    // Frame format is NV12 after decoded by VideoToolbox in ffmpeg
    format = avcodec_enable_hardware_decoding() ? SDL_PIXELFORMAT_NV12 : format;
    printf("SDL_CreateTexture_hijack format: %s\n",
           format == SDL_PIXELFORMAT_NV12 ? "SDL_PIXELFORMAT_NV12" : "SDL_PIXELFORMAT_YV12");
    return SDL_CreateTexture(renderer, format, access, w, h);
}

// Hijack SDL_SDL_UpdateYUVTexture to render NV12 texture
int SDL_UpdateYUVTexture_hijack(SDL_Texture * texture,
                                                 const SDL_Rect * rect,
                                                 const Uint8 *Yplane, int Ypitch,
                                                 const Uint8 *Uplane, int Upitch,
                                                 const Uint8 *Vplane, int Vpitch)
{
    if (avcodec_enable_hardware_decoding()) {
        return SDL_UpdateNVTexture(texture, rect, Yplane, Ypitch, Uplane, Upitch);
    }
    return SDL_UpdateYUVTexture(texture, rect, Yplane, Ypitch, Uplane, Upitch, Vplane, Vpitch);
}

void
sc_video_buffer_consume(struct sc_video_buffer *vb, AVFrame *dst);
// Hijack sc_video_buffer_consume to convert NV12 pixels
void
sc_video_buffer_consume_hijack(struct sc_video_buffer *vb, AVFrame *dst) {
    sc_video_buffer_consume(vb, dst);
    
    // Convert NV12 pixels
    if (avcodec_enable_hardware_decoding()) {
        convert_to_metal_frame(dst);
    }
}
