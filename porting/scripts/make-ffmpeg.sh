#!/bin/bash

OUTPUT=$(cd $OUTPUT && pwd);
BUILD_DIR=$(mktemp -d -t ffmpeg);
cd $BUILD_DIR;

curl -O -L https://downloads.sourceforge.net/project/ffmpeg-ios/ffmpeg-ios-master.tar.bz2;
bunzip2 ffmpeg-ios*.bz2;
tar xvf ffmpeg-ios*.tar;
cp -av FFmpeg-iOS/include/* $OUTPUT/include;
cp -av FFmpeg-iOS/lib/* $OUTPUT/iphone;

[[ -d "$BUILD_DIR" ]] && rm -rf $BUILD_DIR;
