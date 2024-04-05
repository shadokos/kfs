DOCKER_CMD ?= docker
DOCKER_STAMP = .zig-docker
DOCKERFILE_DIR = build/docker

$(DOCKER_STAMP): $(DOCKERFILE_DIR)/Dockerfile
	$(DOCKER_CMD) build -t zig $(DOCKERFILE_DIR)
	$(DOCKER_CMD) volume create --name $(VOLUME_NAME) --driver=local --opt type=none --opt device=$(PWD) --opt o=bind,uid=$(shell id -u)
		> $(DOCKER_STAMP)

VOLUME_NAME=kfs
ZIG = $(DOCKER_CMD) run --rm -w /build -v $(VOLUME_NAME):/build:rw -ti zig zig

build: $(DOCKER_STAMP)
debug: $(DOCKER_STAMP)
release: $(DOCKER_STAMP)
fast: $(DOCKER_STAMP)

.PHONY: run
run: build
	qemu-system-i386 -cdrom kfs.iso