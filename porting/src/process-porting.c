//
//  process-fix.c
//  scrcpy
//
//  Created by Ethan on 2022/2/10.
//

#include "util/process.c"

// Handle sc_process_execute_p to execute adb commands via libadb
#define sc_process_execute_p(...)   sc_process_execute_p__hijack(__VA_ARGS__)
#define sc_pipe_read_all_intr(...)  sc_pipe_read_all_intr__hijack(__VA_ARGS__)
#define sc_process_wait(...)  sc_process_wait__hijack(__VA_ARGS__)
#define sc_process_terminate(...)  sc_process_terminate__hijack(__VA_ARGS__)

#include "sys/unix/process.c"
#include "util/process_intr.c"

#undef sc_process_execute_p
#undef sc_pipe_read_all_intr
#undef sc_process_wait
#undef sc_process_terminate
