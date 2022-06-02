libs: update-all porting scrcpy-server

update-all:
	git submodule update --init --recursive

libscrcpy:
	mkdir -pv output/{iphone,android}
	make -C porting

scrcpy-server:
	curl -o output/scrcpy-server -L https://github.com/Genymobile/scrcpy/releases/download/$$(cd scrcpy && git branch --show-current)/scrcpy-server-$$(cd scrcpy && git branch --show-current)
