ZIG_VERSION ?= 0.13.0
ZIG_LOCAL = zig-linux-x86_64-$(ZIG_VERSION)/zig

ifeq ($(shell which zig),)
    run: install_zig
    build: install_zig
    debug: install_zig
    release: install_zig
    fast: install_zig
    format: install_zig
    clean: uninstall_zig

    ZIG ?= $(ZIG_LOCAL)
endif

ZIG ?= $(shell ls "$(ZIG_LOCAL)" 2>/dev/null || echo zig)

.PHONY: zig_warning
zig_warning:
	@TERM=xterm tput setaf 3
	@echo "WARNING: Zig is not installed. Trying to use a local version (v$(ZIG_VERSION))."
	@TERM=xterm tput sgr0

.PHONY: install_zig
install_zig: $(ZIG_LOCAL) zig_warning

.PHONY: uninstall_zig
uninstall_zig:
	rm -rf zig-linux-x86_64-$(ZIG_VERSION)

$(ZIG_LOCAL):
	curl -sSfL https://ziglang.org/download/$(ZIG_VERSION)/zig-linux-x86_64-$(ZIG_VERSION).tar.xz | tar -xJ