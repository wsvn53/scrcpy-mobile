
cmake_minimum_required(VERSION 3.18.1)

project("scrcpy")

add_library( # Sets the name of the library.
        scrcpy
        # Sets the library as a shared library.
        STATIC
        # Sources of scrcpy
        ../../scrcpy/app/src/control_msg.c

        # Replace with porting version of cotnroller.c
        # ../../scrcpy/app/src/controller.c
        ../../porting/src/controller-porting.c

        ../../scrcpy/app/src/recorder.c

        # av_alloc_context has been moved to demuxer since v2.0
        # ../../scrcpy/app/src/demuxer.c
        ../../porting/src/demuxer-porting.c

        ../../scrcpy/app/src/cli.c
        ../../scrcpy/app/src/receiver.c
        ../../scrcpy/app/src/compat.c
        ../../scrcpy/app/src/util/log.c
        ../../scrcpy/app/src/util/net_intr.c
        ../../scrcpy/app/src/util/thread.c
        ../../scrcpy/app/src/util/term.c
        ../../scrcpy/app/src/util/process.c
        ../../scrcpy/app/src/util/str.c
        ../../scrcpy/app/src/util/process_intr.c
        ../../scrcpy/app/src/util/strbuf.c
        ../../scrcpy/app/src/util/net.c
        ../../scrcpy/app/src/util/file.c
        ../../scrcpy/app/src/util/acksync.c
        ../../scrcpy/app/src/util/tick.c
        ../../scrcpy/app/src/util/intmap.c
        ../../scrcpy/app/src/util/intr.c

        # Replace with porting version of scrcpy.c
        # ../../scrcpy/app/src/scrcpy.c
        ../../porting/src/scrcpy-porting.c

        ../../scrcpy/app/src/v4l2_sink.c

        # Replace with porting version of screen.c
        # ../../scrcpy/app/src/screen.c
        ../../porting/src/screen-porting.c

        ../../scrcpy/app/src/fps_counter.c
        ../../scrcpy/app/src/clock.c
        ../../scrcpy/app/src/frame_buffer.c
        ../../scrcpy/app/src/server.c
        ../../scrcpy/app/src/file_pusher.c

        # Disable usb sources
        # ../../scrcpy/app/src/usb/usb.c
        # ../../scrcpy/app/src/usb/aoa_hid.c
        # ../../scrcpy/app/src/usb/screen_otg.c
        # ../../scrcpy/app/src/usb/hid_mouse.c
        # ../../scrcpy/app/src/usb/scrcpy_otg.c
        # ../../scrcpy/app/src/usb/hid_keyboard.c

        ../../scrcpy/app/src/adb/adb.c
        ../../scrcpy/app/src/adb/adb_device.c
        ../../scrcpy/app/src/adb/adb_tunnel.c
        ../../scrcpy/app/src/adb/adb_parser.c

        # Remove windows platform sources
        # ../../scrcpy/app/src/sys/win/process.c
        # ../../scrcpy/app/src/sys/win/file.c

        # Replace process.c to porting version
        # ../../scrcpy/app/src/sys/unix/process.c
        ../../porting/src/process-porting.c
        # Add process manager
        ../../porting/src/process-porting.cpp
        ../../scrcpy/app/src/sys/unix/file.c

        # Use porting main.c
        # ../../scrcpy/app/src/main.c
        ../../porting/src/main-porting.c

        ../../scrcpy/app/src/opengl.c
        ../../scrcpy/app/src/version.c

        # Replace decoder.c to porting version
        # ../../scrcpy/app/src/decoder.c
        ../../porting/src/decoder-porting.c
        ../../scrcpy/app/src/device_msg.c
        ../../scrcpy/app/src/input_manager.c
        ../../scrcpy/app/src/icon.c
        ../../scrcpy/app/src/options.c

        # Added from v2.0
        ../../porting/src/audio_player-porting.c
        ../../scrcpy/app/src/delay_buffer.c
        ../../scrcpy/app/src/packet_merger.c
        ../../scrcpy/app/src/util/memory.c
        ../../scrcpy/app/src/util/average.c
        ../../scrcpy/app/src/util/rand.c
        ../../scrcpy/app/src/trait/frame_source.c
        ../../scrcpy/app/src/trait/packet_source.c

        # Added from v2.2
        ../../porting/src/display-porting.c
        ../../scrcpy/app/src/util/timeout.c

        # Added from v3.0.2
        ../../scrcpy/app/src/events.c
        ../../scrcpy/app/src/keyboard_sdk.c
        ../../scrcpy/app/src/mouse_sdk.c
        ../../scrcpy/app/src/hid/hid_gamepad.c
        ../../scrcpy/app/src/hid/hid_keyboard.c
        ../../scrcpy/app/src/hid/hid_mouse.c
        ../../scrcpy/app/src/uhid/gamepad_uhid.c
        ../../scrcpy/app/src/uhid/keyboard_uhid.c
        ../../scrcpy/app/src/uhid/mouse_uhid.c
        ../../scrcpy/app/src/uhid/uhid_output.c
        ../../scrcpy/app/src/util/audiobuf.c
        ../../scrcpy/app/src/audio_regulator.c
        ../../scrcpy/app/src/mouse_capture.c
        ../../scrcpy/app/src/util/env.c
        )

target_include_directories(
        scrcpy
        PRIVATE
        .
        ../include
        ../../scrcpy/app/src
        ../../scrcpy/x/app
        ../../output/include
        ../../external/adb-mobile/output/include
        ../../external/adb-mobile/android-tools/vendor/boringssl/include
        )

target_compile_options(
        scrcpy
        PRIVATE
        -include porting.h
        )

target_link_options(scrcpy
        PRIVATE
        ../../output/iphone/libSDL2.a
        ../../output/iphone/libswscale.a
        ../../output/iphone/libswresample.a
        ../../output/iphone/libavutil.a
        ../../output/iphone/libavformat.a
        ../../output/iphone/libavfilter.a
        ../../output/iphone/libavdevice.a
        ../../output/iphone/libavcodec.a
        )

set(CMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY "")
set(CMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD "c++0x")

#set_target_properties(scrcpy
#        PROPERTIES
#        STATIC_LIBRARY_FLAGS "../../output/iphone/libSDL2.a \
#        ../../output/iphone/libswscale.a        \
#        ../../output/iphone/libswresample.a     \
#        ../../output/iphone/libavutil.a         \
#        ../../output/iphone/libavformat.a       \
#        ../../output/iphone/libavfilter.a       \
#        ../../output/iphone/libavdevice.a       \
#        ../../output/iphone/libavcodec.a        \
#        ")
