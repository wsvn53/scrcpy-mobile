all: scrcpy-init adb-mobile libsdl ffmpeg scrcpy

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
	export SCRCPY_VERSION=1.24 && cd server && rm -rf scrcpy-* && \
		curl -o scrcpy.zip -L https://github.com/Genymobile/scrcpy/archive/refs/tags/v$$SCRCPY_VERSION.zip && \
		unzip scrcpy.zip && find src -name "*.java" -exec cp -v {} scrcpy-$$SCRCPY_VERSION/server/{} \;
	