MLIBC_SRC = $(CURDIR)/mlibc
MLIBC_BUILD = $(CURDIR)/mlibc-build
SYSROOT = $(CURDIR)/sysroot
MLIBC_CROSS_FILE = $(CURDIR)/toolchain/shadokos-i686.cross
MESON ?= meson
NINJA ?= ninja
MLIBC_PATH = $(CURDIR)/toolchain/bin:$(PATH)

$(MLIBC_BUILD)/headers/build.ninja:
	PATH="$(MLIBC_PATH)" $(MESON) setup \
		--cross-file $(MLIBC_CROSS_FILE) \
		--prefix=/usr \
		-Dheaders_only=true \
		$(MLIBC_BUILD)/headers $(MLIBC_SRC)

.PHONY: libc-headers
libc-headers: $(MLIBC_BUILD)/headers/build.ninja
	DESTDIR=$(SYSROOT) $(NINJA) -C $(MLIBC_BUILD)/headers install
