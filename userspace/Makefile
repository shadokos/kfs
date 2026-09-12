
DOCKER=docker run -v .:/mount -it shadok


all: bin/dash bin/mount bin/su bin/cat bin/setsid bin/whoami

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

bin/cat: cat/cat.c
	$(DOCKER) i686-shadokos-gcc $< -o $@

bin/setsid: setsid/setsid.c
	$(DOCKER) i686-shadokos-gcc $< -o $@

bin/whoami: whoami/whoami.c
	$(DOCKER) i686-shadokos-gcc $< -o $@
