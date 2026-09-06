# get the last bootloader option
BOOTLOADER ?= $(shell echo $$(ls ".bootloader-"* 2>/dev/null || echo limine) | cut -d'-' -f2)

# get the last optimize option
OPTIMIZE ?= $(shell echo $$(ls ".optimize-"* 2>/dev/null || echo ReleaseSafe) | cut -d'-' -f2)

BUILD_ARGS ?= --summary all --verbose -Dbootloader=$(BOOTLOADER)
QEMU_BOOT_DRIVE ?= -hda kfs.iso

# ext2 image appended to the iso, so userland binaries have somewhere to live.
FS = fs.iso
FS_UUID = 8581277f-6f63-447a-8d0c-347e180d2466
QEMU_DRIVE ?=

# COM1 on the terminal. signal=off keeps Ctrl-C for the guest instead of
# letting it kill qemu, which is what makes /dev/ttyS0 usable as a terminal.
# Repeat -serial to give the kernel more ports to probe.
QEMU_SERIAL ?= -chardev stdio,id=serial0,signal=off -serial chardev:serial0

.PHONY: all
all: build

-include build/Makefiles/Zig.mk
-include build/Makefiles/Docker.mk
-include build/Makefiles/Themes.mk
-include build/Makefiles/CI.mk
-include build/Makefiles/Limine.mk
-include build/Makefiles/Mlibc.mk

.PHONY: run
run: build
	qemu-system-i386 $(QEMU_BOOT_DRIVE) $(QEMU_DRIVE) $(QEMU_SERIAL)


.PHONY: build
build: .optimize-$(OPTIMIZE) .bootloader-$(BOOTLOADER) $(FS)
	$(ZIG) build -Doptimize=$(OPTIMIZE) $(BUILD_ARGS)

.PHONY: debug
debug: .optimize-Debug .bootloader-$(BOOTLOADER)
	$(ZIG) build -Doptimize=Debug $(BUILD_ARGS)

.PHONY: release
release: .optimize-ReleaseSafe .bootloader-$(BOOTLOADER)
	$(ZIG) build -Doptimize=ReleaseSafe $(BUILD_ARGS)

.PHONY: small
small: .optimize-ReleaseSmall .bootloader-$(BOOTLOADER)
	$(ZIG) build -Doptimize=ReleaseFast $(BUILD_ARGS)

.PHONY: fast
fast: .optimize-ReleaseFast .bootloader-$(BOOTLOADER)
	$(ZIG) build -Doptimize=ReleaseFast $(BUILD_ARGS)

$(FS): iso/
	mkfs -F -t ext2 -U $(FS_UUID) -d iso ./$(FS) 10M

.optimize-%:
	rm -rf .optimize-*
	touch $@

.bootloader-%:
	rm -rf .zig-cache
	rm -rf .bootloader-*
	touch $@

.PHONY: debug-server
debug-server: debug
	pkill -f 'qemu.* -[^ ]*s' || true
	qemu-system-i386 $(QEMU_BOOT_DRIVE) $(QEMU_DRIVE) -s -S 1>/dev/null 2>/dev/null &

.PHONY: clean
clean:
	rm -rf .zig-cache

.PHONY: fclean
fclean: clean
	rm -rf .zig-out .optimize-* .bootloader-* kfs.iso $(FS)

.PHONY: format
format:
	ZIG="$(ZIG)" .github/pre-commit
