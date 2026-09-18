
DOCKER=docker run -v .:/mount -it shadokos-toolchain

BIN_DIR=bin

BINS=$(patsubst %.c,$(BIN_DIR)/%,$(wildcard *.c))

all: $(BIN_DIR) bin/dash $(BINS) busybox

dash/Makefile:
	$(DOCKER) bash -c "cd dash; ./autogen.sh ; CC=/toolchain/usr/bin/i686-shadokos-gcc ./configure --host=/toolchain/usr/bin/i686-shadokos-gcc"

dash/src/dash: dash/Makefile
	$(DOCKER) bash -c "cd dash; make"
	$(DOCKER) strip $@

bin/dash: dash/src/dash
	cp $< $@

bin/%: %.c
	$(DOCKER) i686-shadokos-gcc $< -o $@
	$(DOCKER) strip $@

.PHONY: busybox
busybox:
	$(DOCKER) make -C busybox install
	

$(BIN_DIR):
	mkdir $@
