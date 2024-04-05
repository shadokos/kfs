BUILD_ARGS ?= --summary all --verbose

# get the last optimize option
OPTIMIZE ?= $(shell echo $$(ls .optimize-* 2>/dev/null || echo Debug) | cut -d'-' -f2)

.PHONY: all
all: build

ifndef DOCKER
    ZIG ?= zig

    .PHONY: run
    run:
		$(ZIG) build -Doptimize=$(OPTIMIZE) run $(BUILD_ARGS)
else
    -include build/Makefiles/Docker.mk
endif

.PHONY: build
build:
	$(ZIG) build -Doptimize=$(OPTIMIZE) $(BUILD_ARGS)

.PHONY: debug
debug: .optimize-Debug
	$(ZIG) build -Doptimize=Debug $(BUILD_ARGS)

.PHONY: release
release: .optimize-ReleaseSafe
	$(ZIG) build -Doptimize=ReleaseSafe $(BUILD_ARGS)

.PHONY: fast
fast: .optimize-ReleaseFast
	$(ZIG) build -Doptimize=ReleaseFast $(BUILD_ARGS)

.optimize-%:
	rm -rf .optimize-*
	touch $@

.PHONY: clean
clean:
    # || true forces the makefile to ignore the error
	$(ZIG) build uninstall $(BUILD_ARGS) || true

.PHONY: fclean
fclean: clean
	rm -rf zig-cache zig-out .optimize-*