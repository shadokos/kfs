# get the last bootloader option
BOOTLOADER ?= $(shell echo $$(ls ".bootloader-"* 2>/dev/null || echo limine) | cut -d'-' -f2)

# get the last optimize option
OPTIMIZE ?= $(shell echo $$(ls ".optimize-"* 2>/dev/null || echo ReleaseSafe) | cut -d'-' -f2)

BUILD_ARGS ?= --summary all --verbose -Dbootloader=$(BOOTLOADER)
QEMU_BOOT_DRIVE ?= -cdrom kfs.iso
QEMU_DRIVE ?= -hda disk.img

.PHONY: all
all: build

-include build/Makefiles/Zig.mk
-include build/Makefiles/Docker.mk
-include build/Makefiles/Themes.mk
-include build/Makefiles/CI.mk
-include build/Makefiles/Limine.mk

.PHONY: run
run: build
	qemu-system-i386 $(QEMU_BOOT_DRIVE) ${QEMU_DRIVE}

.PHONY: curse
curse: build
	qemu-system-i386 $(QEMU_BOOT_DRIVE) ${QEMU_DRIVE} -curses


.PHONY: build
build: .optimize-$(OPTIMIZE) .bootloader-$(BOOTLOADER)
	$(ZIG) build -Doptimize=$(OPTIMIZE) $(BUILD_ARGS) -freference-trace=15

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
	rm -rf .zig-out .optimize-* .bootloader-* kfs.iso

.PHONY: format
format:
	ZIG="$(ZIG)" .github/pre-commit