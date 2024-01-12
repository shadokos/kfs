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
	tty/tty.zig \
	tty/vt100.zig \
	tty/termios.zig \
	tty/keyboard/scanmap.zig \
	tty/keyboard/keymap.zig \
	tty/keyboard/us-std.zig \
	tty/keyboard.zig \
	drivers/ports.zig \
	ft/ascii.zig \
	ft/fmt.zig \
	ft/ft.zig \
	ft/io/fixed_buffer_stream.zig \
	ft/io/reader.zig \
	ft/io/writer.zig \
	ft/io.zig \
	ft/math.zig \
	ft/mem.zig \
	ft/meta.zig

SYMBOL_DIR = $(ZIGCACHE)/symbols
SYMBOL_FILE = $(SYMBOL_DIR)/$(NAME).symbols

SYMBOL_DIR = $(ZIGCACHE)/symbols
SYMBOL_FILE = $(SYMBOL_DIR)/$(NAME).symbols

all: $(ISO)

$(ISO): $(BIN) $(GRUB_CONF)
	grub-mkrescue --compress=xz -o $@ $(ISODIR)

run: $(ISO)
	qemu-system-$(ARCH) -cdrom $<

run_kernel: $(BIN)
	qemu-system-$(ARCH) -kernel $<

$(BIN): $(addprefix $(SRCDIR)/,$(SRC))
	zig build \
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

fclean: clean
	rm -rf $(ISO)

re: fclean all

.PHONY: run all clean fclean re debug
