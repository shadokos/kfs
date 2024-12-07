BUILD_ARGS ?= --summary all --verbose -Dbootloader=$(BOOTLOADER)

# get the last bootloader option
BOOTLOADER ?= $(shell echo $$(ls ".bootloader-"* 2>/dev/null || echo grub) | cut -d'-' -f2)

# get the last optimize option
OPTIMIZE ?= $(shell echo $$(ls ".optimize-"* 2>/dev/null || echo Debug) | cut -d'-' -f2)

.PHONY: all
all: build

-include build/Makefiles/Zig.mk
-include build/Makefiles/Docker.mk
-include build/Makefiles/Themes.mk
-include build/Makefiles/CI.mk
-include build/Makefiles/Limine.mk

.PHONY: run
run: build
	qemu-system-i386 -cdrom kfs.iso

.PHONY: build
build: .optimize-$(OPTIMIZE) .bootloader-$(BOOTLOADER)
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

.optimize-%:
	rm -rf .optimize-*
	touch $@

.bootloader-%:
	rm -rf .zig-cache
	rm -rf .bootloader-*
	touch $@

.PHONY: clean
clean:
    # || true forces the makefile to ignore the error
	$(ZIG) build uninstall $(BUILD_ARGS) || true

.PHONY: fclean
fclean: clean
	rm -rf .zig-cache zig-out .optimize-* .bootloader-*

.PHONY: format
format:
	ZIG="$(ZIG)" .github/pre-commit
