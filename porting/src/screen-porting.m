//
//  screen-porting.m
//  scrcpy-module
//
//  Created by Ethan on 2022/6/3.
//

#import <SDL2/SDL.h>
#import <SDL2/SDL_render.h>
#import <UIKit/UIKit.h>

#define sc_screen_init(...)   sc_screen_init_orig(__VA_ARGS__)

#include "screen.c"

#undef sc_screen_init

struct sc_size
sc_screen_current_frame(struct sc_size new_frame) {
    static struct sc_size current_frame;
    if (new_frame.width > 0 && new_frame.height > 0) {
        current_frame.width = new_frame.width;
        current_frame.height = new_frame.height;
    }
    return current_frame;
}

float screen_scale(void) {
    if ([UIScreen.mainScreen respondsToSelector:@selector(nativeScale)]) {
        return UIScreen.mainScreen.nativeScale;
    }
    return UIScreen.mainScreen.scale;
}

bool
sc_screen_init(struct sc_screen *screen,
               const struct sc_screen_params *params) {
    bool ret = sc_screen_init_orig(screen, params);

    // Set renderer scale
    SDL_RenderSetScale(screen->renderer, screen_scale(), screen_scale());
    
    // Save current screen frame
    sc_screen_current_frame(params->frame_size);

    return ret;
}
