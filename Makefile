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
	../Makefile \
	../build.zig \
	boot.zig \
	trampoline.zig \
	drivers/ps2/ps2.zig \
	gdt.zig \
	drivers/acpi/acpi.zig \
	drivers/acpi/types/acpi.zig \
	drivers/acpi/types/s5.zig \
	drivers/vga/text.zig \
	memory.zig \
	memory/bitmap.zig \
	memory/paging.zig \
	memory/buddy_allocator.zig \
	memory/static_allocator.zig \
	memory/page_frame_allocator.zig \
	memory/kernel_memory_allocator.zig \
	memory/linear_allocator.zig \
	memory/virtual_addresses_allocator.zig \
	memory/early_virtual_addresses_allocator.zig \
	memory/virtual_page_allocator.zig \
	memory/mapping.zig \
	memory/slab.zig \
	memory/cache.zig \
	memory/fuzzer.zig \
	kernel.zig \
	multiboot.zig \
	tty/tty.zig \
	tty/themes.zig \
	tty/vt100.zig \
	tty/termios.zig \
	tty/keyboard/scanmap.zig \
	tty/keyboard/keymap.zig \
	tty/keyboard/keymaps/us-std.zig \
	tty/keyboard/keymaps/french.zig \
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
	ft/Random.zig \
	ft/Random/Xoroshiro128.zig \
	ft/meta.zig \
	shell/token.zig \
	shell/builtins.zig \
	shell/helpers.zig \
	shell/utils.zig \
	shell.zig \
	$(THEME_INDEX)

THEME_LIST = themes

THEME_DIR = tty/themes

THEME_FILES = $(addprefix ${SRCDIR}/${THEME_DIR}/, $(addsuffix .zig, $(shell cat ${THEME_LIST} | tr ' ' '_' | grep -vE '^[[:space:]]*$$')))

THEME_INDEX = $(THEME_DIR)/index.zig

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

${SRCDIR}/$(THEME_DIR):
	mkdir -p $@

$(THEME_FILES): | ${SRCDIR}/$(THEME_DIR)
	FILE=$$(mktemp); \
	wget -O $$FILE "https://raw.githubusercontent.com/Gogh-Co/Gogh/master/themes/$(shell echo $(notdir $(basename $@)) | tr '_' ' ').yml" || exit 1;\
	( \
	echo 'pub const theme = @import("../themes.zig").convert(.{'; \
	printf '\t.palette = .{\n'; \
	cat $$FILE | grep -E 'color_[0-9]+' | grep -E '^.*#([0-9a-fA-F]{6}).*$$' | sed -E 's/.*#([0-9a-fA-F]{6}).*/\t\t@import("..\/..\/drivers\/vga\/text.zig").Color.convert(0x\1),/g'; \
	printf '\t},\n'; \
	printf '\t.background = @import("../../drivers/vga/text.zig").Color.convert('$$(cat $$FILE | grep background | cut -d \' -f 2 | sed 's/#/0x/g' | grep -E '^0x[0-9a-fA-F]{6}$$')'),\n'; \
	printf '\t.foreground = @import("../../drivers/vga/text.zig").Color.convert('$$(cat $$FILE | grep foreground | cut -d \' -f 2 | sed 's/#/0x/g' | grep -E '^0x[0-9a-fA-F]{6}$$')'),\n'; \
	echo '});'; \
	) > $@;\
	rm $$FILE;

${SRCDIR}/$(THEME_INDEX): $(THEME_FILES) | ${SRCDIR}/$(THEME_DIR)
	cat ${THEME_LIST} | tr ' ' '_' | paste -d\| ${THEME_LIST} - | grep -vE '^[[:space:]]*\|[[:space:]]*$$' | sed -E "s/(.*)\|(.*)/pub const @\"\1\" = @import(\"\2.zig\");/g" > ${SRCDIR}/$(THEME_INDEX)

clean:
	rm -rf $(BIN) $(ZIGCACHE) "${SRCDIR}/$(THEME_DIR)" "${SRCDIR}/$(THEME_INDEX)"
	[ -f $(DOCKER_STAMP) ] && { $(DOCKER_CMD) image rm zig && rm $(DOCKER_STAMP) && $(DOCKER_CMD) volume rm $(NAME); } || true

fclean: clean
	rm -rf $(ISO)

re: fclean all

.PHONY: run all clean fclean re debug run_kernel
