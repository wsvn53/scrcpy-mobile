libs: update-all libscrcpy

update-all:
	git submodule update --init --recursive

libscrcpy:
	mkdir -pv output/{iphone,android}
	make -C porting

