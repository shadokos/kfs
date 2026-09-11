ZIG_VERSION ?= 0.15.1
ZIG_LONG = zig-x86_64-linux-$(ZIG_VERSION)
ZIG_LOCAL = $(ZIG_LONG)/zig

ifneq ($(shell zig version 2>/dev/null | grep -q "$(ZIG_VERSION)" && echo "found"),found)
    run: install_zig
    build: install_zig
    debug: install_zig
    release: install_zig
    fast: install_zig
    format: install_zig
    fclean: uninstall_zig

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
	rm -rf $(ZIG_LONG)

$(ZIG_LOCAL):
	curl -sSfL https://ziglang.org/download/$(ZIG_VERSION)/$(ZIG_LONG).tar.xz | tar -xJ
