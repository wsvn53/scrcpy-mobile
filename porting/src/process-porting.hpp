//
//  process-porting.hpp
//  scrcpy
//
//  Created by Ethan on 2022/3/19.
//

#ifndef process_porting_hpp
#define process_porting_hpp

#include <stdio.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef pid_t sc_pid;
typedef int sc_exit_code;
typedef int sc_pipe;

int
sc_process_execute_p(const char *const argv[], sc_pid *pid, unsigned flags,
                     int *pin, int *pout, int *perr);
ssize_t
sc_pipe_read_all_intr(struct sc_intr *intr, sc_pid pid, sc_pipe pipe,
                      char *data, size_t len);
sc_exit_code
sc_process_wait(pid_t pid, bool close);
bool
sc_process_terminate(pid_t pid);

#ifdef __cplusplus
}
#endif

#endif /* process_porting_hpp */
