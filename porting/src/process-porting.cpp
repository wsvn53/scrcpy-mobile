//
//  process-porting.cpp
//  scrcpy-mobile
//
//  Created by Ethan on 2022/3/19.
//

#include "process-porting.hpp"

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include <map>
#include <mutex>
#include <string>
#include <vector>
#include <thread>

extern "C" {
#include "adb_public.h"
}

static inline int array_len(const char *arr[]) {
    int len = 0;
    while (arr[len] != NULL) { len++; }
    return len;
}

/**
 * map tp store retured result of pid
 */

static std::map<pid_t, std::string> sc_result_map;

void sc_store_result(pid_t pid, const char *result) {
    sc_result_map.emplace(pid, std::string(result));
}

const char *sc_retrieve_result(pid_t pid) {
    return sc_result_map[pid].c_str();
}

const char *sc_remove_result(int pid) {
    std::string result = sc_result_map[pid];
    sc_result_map.erase(pid);
    if (result.empty()) {
        return strdup(result.c_str());
    }
    return NULL;
}

/**
 * map to store return success of pid
 */
static std::map<pid_t, bool> sc_success_map;

void sc_store_success(pid_t pid, bool success) {
    sc_success_map.emplace(pid, success);
}

bool sc_retrieve_success(pid_t pid) {
    return sc_success_map[pid];
}

void sc_remove_success(pid_t pid) {
    sc_success_map.erase(pid);
}

/**
 * map to store thread of pid
 */
static std::map<pid_t, std::thread *> sc_thread_map;

void sc_thread_clean() {
    std::map<pid_t, std::thread *> pending_clean;
    for (auto &th : sc_thread_map) {
        auto t = th.second;
        printf("> check thread %p status %d\n", t, t != nullptr && t->joinable());
        if (t == nullptr) pending_clean[th.first] = th.second;
    }

    printf("> cleaning %d/%d threads\n", pending_clean.size(), sc_thread_map.size());
    for (auto &th : pending_clean) {
        sc_thread_map.erase(th.first);
    }
    printf("> thread count after clean: %d\n", sc_thread_map.size());
}

void sc_store_thread(pid_t pid, std::thread *thread) {
    // clean finished thread
    sc_thread_clean();

    // Store thread
    sc_thread_map.emplace(pid, thread);
}

void sc_remove_thread(pid_t pid) {
    sc_thread_map.erase(pid);
    sc_thread_map[pid] = nullptr;
}

std::thread *sc_retrieve_thread(pid_t pid) {
    return sc_thread_map[pid];
}

void adb_process_thread_func(bool *thread_started, pid_t pid, const char *thread_name, const char *adb_args[]) {
    printf("> thread: pid=%d, name=%s started.\n", pid, thread_name);
    
    // Copy args to local variable
    int argc = array_len(adb_args);
    const char *argv[argc];
    std::string command = std::string("");
    for (int i = 0; i < argc; i++) {
        argv[i] = strdup(adb_args[i]);
        char cmd[strlen(argv[i])+2];
        memset(cmd, 0, strlen(argv[i])+2);
        sprintf(cmd, " %s", argv[i]);
        command.append(cmd);
    }
    printf("> adb%s\n", command.c_str());
    
    // Mark thread_started after copied all arguments
    *thread_started = true;
    
    if (argc > 5 && strcmp(argv[4], "app_process") == 0) {
        printf("> scrcpy-server app_process started\n");
    }

    // Change thread name
#ifdef __APPLE__
    pthread_setname_np(thread_name);
#else
    pthread_setname_np(pthread_self(), thread_name);
#endif

    // Execute adb command
    bool success;
    char *result = strdup("");

    std::thread commandline_thread = std::thread([argc, &argv, &result, &success]() {
        int ret_code = adb_commandline_porting(argc, argv, &result);
        success = ret_code == 0;
    });
    commandline_thread.join();

    // deal with commandline occur errors and thread exit
    if (!success && strlen(result) == 0) {
        printf("> commandline_thread failed, save last output\n");
        result = adb_commandline_last_output();
    }

    // Save success
    sc_store_success(pid, success);
    
    // Save result
    sc_store_result(pid, result);
    
    printf("> pid=%d, success=%s\n", pid, success?"true":"false");
    printf("> result:\n%s\n", result?:"(empty)");

    // Remove from sc_thread_map
    sc_thread_map.erase(pid);
    sc_thread_map[pid] = nullptr;
}

int
sc_process_execute_p(const char *const argv[], sc_pid *pid, unsigned flags,
                     int *pin, int *pout, int *perr) {
    // Fake pipe fd
    if (pout != nullptr) {
        int pipe_fd[2];
        pipe(pipe_fd);
        *pout = (sc_pipe)pipe_fd[1];
    }
    
    // Generate fake pid
    *pid = arc4random() % 10000;
    
    // adb arguments start from index 1
    int len = array_len((const char **)argv);
    const char *adb_args[len];
    for (int i = 1; i < len; i++) {
        adb_args[i-1] = strdup(argv[i]);
    }
    adb_args[len-1] = NULL;
    
    // Format thread name
    const char *fmt = "ADB-%d";
    int th_len = std::snprintf(nullptr, 0, fmt, *pid);
    char th_name[th_len+1];
    std::snprintf(th_name, th_len+1, fmt, *pid);
    const char *thread_name = strdup(th_name);
    
    // Create thread
    const char **adb_args_ref = (const char **)adb_args;
    bool thread_started = false;
    std::thread adb_thread = std::thread([&thread_started, pid, thread_name, adb_args_ref]() {
        adb_process_thread_func(&thread_started, *pid, thread_name, adb_args_ref);
    });
    sc_store_thread(*pid, &adb_thread);
    
    // Start thread
    adb_thread.detach();
    
    // Wait thread start, avoid variable be released
    while (thread_started == false) {
        usleep(10000);
    }
    
    return 0;
}

ssize_t
sc_pipe_read_all_intr(struct sc_intr *intr, sc_pid pid, sc_pipe pipe,
                      char *data, size_t len) {
    // Wait thread exited to read result
    sc_process_wait(pid, false);
    const char *result = sc_retrieve_result(pid);
    result = result ? : "";
    strcpy(data, result);
    return strlen(result) > len ? len : strlen(result);
}

sc_exit_code
sc_process_wait(pid_t pid, bool close) {
    std::thread *adb_thread = sc_retrieve_thread(pid);
    if (adb_thread == nullptr) {
        return sc_retrieve_success(pid)?0:1;
    }
    
    while((adb_thread = sc_retrieve_thread(pid)) && adb_thread != nullptr) {
        usleep(10000);
    }
    
    printf("> wait pid=%d, result=%s\n", pid, sc_retrieve_success(pid)?"true":"false");
    return sc_retrieve_success(pid)?0:1;
}

bool
sc_process_terminate(pid_t pid) {
    std::thread *adb_thread = sc_retrieve_thread(pid);
    if (adb_thread == nullptr) {
        return true;
    }
    
    printf("> sc_process_terminate, thread pid: %d\n", pid);
    sc_remove_thread(pid);
    
    return true;
}
