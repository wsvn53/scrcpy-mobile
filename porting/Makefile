all: scrcpy-init adb-mobile libsdl ffmpeg scrcpy scrcpy-server

scrcpy-init:
	cd ../scrcpy && rm -rf x && meson x --buildtype release --strip -Db_lto=true -Dportable=true -Dusb=false

adb-mobile:
	make -C ../external/adb-mobile

libsdl:
	OUTPUT=../output bash ./scripts/make-libsdl.sh

ffmpeg:
	OUTPUT=../output bash ./scripts/make-ffmpeg.sh

scrcpy:
	OUTPUT=../output TARGET=scrcpy/iphoneos/arm64 bash ./scripts/make-scrcpy.sh
	OUTPUT=../output TARGET=scrcpy/iphonesimulator/x86_64 bash ./scripts/make-scrcpy.sh
	lipo -create ../output/*/*/libscrcpy.a -output ../output/iphone/libscrcpy.a

scrcpy-server:
	set -x && \
	export SCRCPY_VERSION=3.0.2 && \
	export ANDROID_SDK_ROOT=~/Library/Android/sdk && \
	export JAVA_HOME="$$(/usr/libexec/java_home --version 1.11)" && \
	export PATH="$$JAVA_HOME/bin:$$PATH" && \
	cd server && rm -rf scrcpy-* && \
	curl -o scrcpy.zip -L https://github.com/Genymobile/scrcpy/archive/refs/tags/v$$SCRCPY_VERSION.zip && \
	unzip scrcpy.zip && \
	cd scrcpy-$$SCRCPY_VERSION && \
	meson setup x --buildtype=release --strip -Db_lto=true -Dcompile_app=false -Dcompile_server=true && \
	sed -ibak 's/exit/echo/g' server/scripts/build-wrapper.sh && \
	ninja -Cx -v && \
	find . -type f -name "scrcpy-server" -exec cp -v {} .. \;
