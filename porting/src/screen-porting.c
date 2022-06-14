//
//  screen-porting.c
//  scrcpy-module
//
//  Created by Ethan on 2022/6/3.
//

#include "stdbool.h"
#include <SDL2/SDL.h>
#include <SDL2/SDL_render.h>

bool ScrcpyEnableHardwareDecoding(void);
int SDL_UpdateYUVTexture_hijack(SDL_Texture * texture,
                                const SDL_Rect * rect,
                                const Uint8 *Yplane, int Ypitch,
                                const Uint8 *Uplane, int Upitch,
                                const Uint8 *Vplane, int Vpitch);
void SDL_RenderPresent_hijack(SDL_Renderer * renderer);

#define sc_screen_init(...)   sc_screen_init_orig(__VA_ARGS__)
#define SDL_UpdateYUVTexture(...)   SDL_UpdateYUVTexture_hijack(__VA_ARGS__)
#define SDL_RenderPresent(...)   SDL_RenderPresent_hijack(__VA_ARGS__)
#define sc_video_buffer_consume(...)   sc_video_buffer_consume_hijack(__VA_ARGS__)

#include "screen.c"

#undef sc_screen_init
#undef SDL_UpdateYUVTexture
#undef SDL_RenderPresent
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
void ScrcpyHandleFrame(AVFrame *frame) {}

// Hijack SDL_UpdateYUVTexture
int SDL_UpdateYUVTexture_hijack(SDL_Texture * texture,
                                                 const SDL_Rect * rect,
                                                 const Uint8 *Yplane, int Ypitch,
                                                 const Uint8 *Uplane, int Upitch,
                                                 const Uint8 *Vplane, int Vpitch)
{
    if (ScrcpyEnableHardwareDecoding()) { return 0; }
    return SDL_UpdateYUVTexture(texture, rect, Yplane, Ypitch, Uplane, Upitch, Vplane, Vpitch);
}

void SDL_UpdateCommandGeneration(SDL_Renderer * renderer);
void SDL_RenderPresent_hijack(SDL_Renderer * renderer) {
    if (ScrcpyEnableHardwareDecoding()) {
        // Update renderer_command_generation to fix memory leak when Destory_Texture
        SDL_UpdateCommandGeneration(renderer);
        return;
    }
    SDL_RenderPresent(renderer);
}

void
sc_video_buffer_consume(struct sc_video_buffer *vb, AVFrame *dst);
// Hijack sc_video_buffer_consume to convert NV12 pixels
void
sc_video_buffer_consume_hijack(struct sc_video_buffer *vb, AVFrame *dst) {
    sc_video_buffer_consume(vb, dst);
    
    // Handle hardware frame render
    if (ScrcpyEnableHardwareDecoding()) ScrcpyHandleFrame(dst);
}
