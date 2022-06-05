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

struct sc_screen *
sc_screen_current_screen(struct sc_screen *screen) {
    static struct sc_screen *current_screen;
    if (screen != NULL) {
        current_screen = screen;
    }
    return current_screen;
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
    
    // Save current screen pointer
    sc_screen_current_screen(screen);

    return ret;
}
