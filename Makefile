libs: update-all porting

update-all:
	git submodule update --init --recursive

libscrcpy:
	mkdir -pv output/{iphone,android}
	make -C porting
