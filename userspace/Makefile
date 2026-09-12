
DOCKER=docker run -v .:/mount -it shadok


all: bin/dash bin/mount bin/su

dash/Makefile:
	$(DOCKER) bash -c "cd dash; ./autogen.sh ; CC=/toolchain/usr/bin/i686-shadokos-gcc ./configure --host=/toolchain/usr/bin/i686-shadokos-gcc"

dash/src/dash: dash/Makefile
	$(DOCKER) bash -c "cd dash; make"

bin/dash: dash/src/dash
	cp $< $@

bin/su: su/su.c
	$(DOCKER) i686-shadokos-gcc $< -o $@

bin/mount: mount/mount.c
	$(DOCKER) i686-shadokos-gcc $< -o $@
