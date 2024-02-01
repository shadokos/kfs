NAME=kfs

ISO=$(NAME).iso

ISODIR=iso

BOOTDIR=$(ISODIR)/boot

BIN=$(BOOTDIR)/bin/$(NAME).elf

ZIGCACHE=.cache

GRUB_CONF=$(BOOTDIR)/grub/grub.cfg

ARCH=i386

SRCDIR = src

SRC = linker.ld \
	../build.zig \
	boot.zig \
	kernel.zig \
	multiboot.zig \
	tty/tty.zig \
	tty/vt100.zig \
	tty/termios.zig \
	tty/keyboard/scanmap.zig \
	tty/keyboard/keymap.zig \
	tty/keyboard/us-std.zig \
	tty/keyboard.zig \
	io/ports.zig \
	ft/ascii.zig \
	ft/debug.zig \
	ft/fmt.zig \
	ft/ft.zig \
	ft/io/fixed_buffer_stream.zig \
	ft/io/reader.zig \
	ft/io/writer.zig \
	ft/io.zig \
	ft/math.zig \
	ft/mem.zig \
	ft/meta.zig \
	shell/token.zig \
	shell/builtins.zig \
	shell/helpers.zig \
	shell/utils.zig \
	shell.zig \

SYMBOL_DIR = $(ZIGCACHE)/symbols
SYMBOL_FILE = $(SYMBOL_DIR)/$(NAME).symbols

DOCKER_CMD ?= docker

DOCKER_STAMP = .zig-docker

all: $(ISO)

ifndef DOCKER

ZIG = zig
GRUB_MKRESCUE = grub-mkrescue

else

$(BIN): $(DOCKER_STAMP)
ZIG = $(DOCKER_CMD) run --rm -w /build -v $(NAME):/build:rw -ti zig zig

$(ISO): $(DOCKER_STAMP)
GRUB_MKRESCUE = $(DOCKER_CMD) run --rm -w /build -v $(NAME):/build:rw -ti zig grub-mkrescue

endif

$(ISO): $(BIN) $(GRUB_CONF)
	$(GRUB_MKRESCUE) --compress=xz -o $@ $(ISODIR)

run: $(ISO)
	qemu-system-$(ARCH) -cdrom $<

run_kernel: $(BIN)
	qemu-system-$(ARCH) -kernel $<

$(DOCKER_STAMP): dockerfile
	$(DOCKER_CMD) build -t zig .
	$(DOCKER_CMD) volume create --name $(NAME) --driver=local --opt type=none --opt device=$(PWD) --opt o=bind,uid=$(shell id -u)
	> $(DOCKER_STAMP)


$(BIN): $(addprefix $(SRCDIR)/,$(SRC))
	$(ZIG) build \
		--prefix $(BOOTDIR) \
		-Dname=$(notdir $(BIN)) \
		-Doptimize=ReleaseSafe \
		--cache-dir $(ZIGCACHE) \
		--summary all \
		--verbose

debug: all $(SYMBOL_FILE)
	( qemu-system-$(ARCH) -cdrom $(ISO) -s -S 1>/dev/null 2>/dev/null \
	|	gdb  -ex "file $(BIN)" -ex "target remote localhost:1234" <&3 ) 3<&0

$(SYMBOL_DIR):
	mkdir -p $(SYMBOL_DIR)

$(SYMBOL_FILE): | $(SYMBOL_DIR)
	objcopy --only-keep-debug $(BIN) $(SYMBOL_FILE)

clean:
	rm -rf $(BIN) $(ZIGCACHE)
	[ -f $(DOCKER_STAMP) ] && { $(DOCKER_CMD) image rm zig && rm $(DOCKER_STAMP) && $(DOCKER_CMD) volume rm $(NAME); } || true

fclean: clean
	rm -rf $(ISO)

re: fclean all

.PHONY: run all clean fclean re debug run_kernel
