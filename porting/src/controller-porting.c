//
//  controller-porting.c
//  scrcpy-mobile
//
//  Created by Ethan on 2022/6/2.
//

#define sc_controller_push_msg(...)     sc_controller_push_msg_hijack(__VA_ARGS__)

#include "controller.c"

#undef sc_controller_push_msg

// Defined in screen-porting.m
struct sc_size
sc_screen_current_frame(struct sc_size new_frame);

// Fix negative point values and larger than screen size
bool sc_controller_push_msg(struct sc_controller *controller,
                            struct sc_control_msg *msg) {
    if (msg->type == SC_CONTROL_MSG_TYPE_INJECT_TOUCH_EVENT) {
        // x/y is negative
        msg->inject_touch_event.position.point.x = msg->inject_touch_event.position.point.x < 0 ? 0 : msg->inject_touch_event.position.point.x;
        msg->inject_touch_event.position.point.y = msg->inject_touch_event.position.point.y < 0 ? 0 : msg->inject_touch_event.position.point.y;
        
        // x/y exceed max frame size
        struct sc_size screen_size;
        screen_size = sc_screen_current_frame(screen_size);
        if (screen_size.width > 0 && screen_size.height > 0) {
            msg->inject_touch_event.position.point.x = msg->inject_touch_event.position.point.x > screen_size.width ? screen_size.width : msg->inject_touch_event.position.point.x;
            msg->inject_touch_event.position.point.y = msg->inject_touch_event.position.point.y > screen_size.height ? screen_size.height : msg->inject_touch_event.position.point.y;
        }
    }
    
    return sc_controller_push_msg_hijack(controller, msg);
}
