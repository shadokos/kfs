NAME=kfs

ISO=$(NAME).iso

ISODIR=iso

BOOTDIR=$(ISODIR)/boot

BIN=$(BOOTDIR)/bin/$(NAME).elf

ZIGCACHE=.cache

GRUB_CONF=$(BOOTDIR)/grub/grub.cfg

ARCH=i386

SRCDIR = src
SRC = linker.ld kernel.zig

all: $(ISO)

$(ISO): $(BIN) $(GRUB_CONF)
	grub-mkrescue -o $@ $(ISODIR)

run: $(ISO)
	qemu-system-$(ARCH) -cdrom $<

$(BIN): $(addprefix $(SRCDIR)/,$(SRC))
	zig build --prefix $(BOOTDIR) -Dname=$(notdir $(BIN)) --summary all --cache-dir $(ZIGCACHE)

FORCE:

clean:
	rm -rf $(BIN) $(ZIGCACHE)

fclean: clean
	rm -rf $(ISO)

re: fclean all

.PHONY: run all clean fclean re
