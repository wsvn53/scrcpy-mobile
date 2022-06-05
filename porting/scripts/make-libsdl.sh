#!/bin/bash

set -x;

OUTPUT=$(cd $OUTPUT && pwd);
BUILD_DIR=$(mktemp -d -t SDL);
cd $BUILD_DIR;

curl -O https://www.libsdl.org/release/SDL2-2.0.22.tar.gz;
tar xzvf SDL*.tar.gz;

# Build iOS Libraries
echo "=> Building for iOS..";

xcodebuild clean build OTHER_CFLAGS="-fembed-bitcode" \
	BUILD_DIR=$BUILD_DIR/build \
	ARCHS="arm64" \
	CONFIGURATION=Debug \
    GCC_PREPROCESSOR_DEFINITIONS='CFRunLoopRunInMode=CFRunLoopRunInMode_fix' \
	-project SDL2-*/Xcode/SDL/SDL.xcodeproj -scheme "Static Library-iOS" -sdk iphoneos;
xcodebuild clean build OTHER_CFLAGS="-fembed-bitcode" \
	BUILD_DIR=$BUILD_DIR/build \
	ARCHS="x86_64" \
	CONFIGURATION=Debug \
    GCC_PREPROCESSOR_DEFINITIONS='CFRunLoopRunInMode=CFRunLoopRunInMode_fix' \
	-project SDL2-*/Xcode/SDL/SDL.xcodeproj -scheme "Static Library-iOS" -sdk iphonesimulator;

lipo -create build/*/libSDL2.a -output build/libSDL2.a;
file build/libSDL2.a;

[[ -d "$OUTPUT/include/SDL2" ]] || mkdir -pv $OUTPUT/include/SDL2;
[[ -d "$OUTPUT/iphone" ]] || mkdir -pv $OUTPUT/iphone;
[[ -d "$OUTPUT/iphone" ]] && {
	cp -v build/libSDL2.a $OUTPUT/iphone;
	cp -v SDL2-*/include/*.h $OUTPUT/include/SDL2;
}

# echo "=> Building for Android..";

# # if mac arm64 host, run with x86_64 by arch command
# ARCH_RUN="";
# uname -m | grep arm64 && {
# 	ARCH_RUN="arch -x86_64";
# }

# # Check android sdk home
# [[ -z "$ANDROID_HOME" ]] && echo "No ANDROID_HOME set" && exit 1;

# PATH=$PATH:$(dirname "$(find $ANDROID_HOME -name "ndk-build" | tail -n1)") $ARCH_RUN sh ./SDL2-*/build-scripts/androidbuildlibs.sh
# [[ -d $OUTPUT/lib/android ]] || mkdir -pv $OUTPUT/lib/android/{arm64-v8a,armeabi-v7a,x86,x86_64};

# cp -av SDL2-*/build/android/lib/arm64-v8a/* $OUTPUT/lib/android/arm64-v8a;
# cp -av SDL2-*/build/android/lib/armeabi-v7a/* $OUTPUT/lib/android/armeabi-v7a;
# cp -av SDL2-*/build/android/lib/x86/* $OUTPUT/lib/android/x86;
# cp -av SDL2-*/build/android/lib/x86_64/* $OUTPUT/lib/android/x86_64;

[[ -d "$BUILD_DIR" ]] && rm -rf $BUILD_DIR;
