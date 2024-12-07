LIMINE_DIR=limine
LIMINE_BIN=$(LIMINE_DIR)/limine

.PHONY: limine
limine: $(LIMINE_BIN)

$(LIMINE_BIN):
	git clone https://github.com/limine-bootloader/limine.git --branch=v8.x-binary --depth=1 $(LIMINE_DIR)
	$(MAKE) -C $(LIMINE_DIR)

.PHONY: limine_clean
limine_clean:
	rm -rf $(LIMINE_DIR)
