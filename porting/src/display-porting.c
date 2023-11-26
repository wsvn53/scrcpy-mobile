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

#define SDL_UpdateYUVTexture(...)   SDL_UpdateYUVTexture_hijack(__VA_ARGS__)
#define SDL_RenderPresent(...)   SDL_RenderPresent_hijack(__VA_ARGS__)

#include "display.c"

#undef SDL_UpdateYUVTexture
#undef SDL_RenderPresent

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
