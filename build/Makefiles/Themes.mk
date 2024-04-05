THEME_LIST = themes
THEME_DIR = tty/themes
THEME_FILES = $(addprefix ${SRCDIR}/${THEME_DIR}/, $(addsuffix .zig, $(shell cat ${THEME_LIST} | tr ' ' '_' | grep -vE '^[[:space:]]*$$')))
THEME_INDEX = $(THEME_DIR)/index.zig

SRCDIR ?= ./src

.PHONY: install_themes
install_themes: $(SRCDIR)/$(THEME_INDEX)

${SRCDIR}/$(THEME_DIR):
	mkdir -p $@

$(THEME_FILES): | ${SRCDIR}/$(THEME_DIR)
	FILE=$$(mktemp); \
	wget -O $$FILE "https://raw.githubusercontent.com/Gogh-Co/Gogh/master/themes/$(shell echo $(notdir $(basename $@)) | tr '_' ' ').yml" 2>&1 || exit 1;\
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
	zig fmt ${SRCDIR}/$(THEME_DIR) 1>/dev/null
