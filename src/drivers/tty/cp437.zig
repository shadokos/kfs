const std = @import("std");

/// Mapping UTF-8 code points to CP437 characters
const unicode_to_cp437 = std.StaticStringMap(u8).initComptime(.{
    // Extended Latin characters (0x80-0x9F)
    .{ "Ç", 0x80 },  .{ "ü", 0x81 },  .{ "é", 0x82 },  .{ "â", 0x83 },
    .{ "ä", 0x84 },  .{ "à", 0x85 },  .{ "å", 0x86 },  .{ "ç", 0x87 },
    .{ "ê", 0x88 },  .{ "ë", 0x89 },  .{ "è", 0x8A },  .{ "ï", 0x8B },
    .{ "î", 0x8C },  .{ "ì", 0x8D },  .{ "Ä", 0x8E },  .{ "Å", 0x8F },
    .{ "É", 0x90 },  .{ "æ", 0x91 },  .{ "Æ", 0x92 },  .{ "ô", 0x93 },
    .{ "ö", 0x94 },  .{ "ò", 0x95 },  .{ "û", 0x96 },  .{ "ù", 0x97 },
    .{ "ÿ", 0x98 },  .{ "Ö", 0x99 },  .{ "Ü", 0x9A },  .{ "¢", 0x9B },
    .{ "£", 0x9C },  .{ "¥", 0x9D },  .{ "₧", 0x9E }, .{ "ƒ", 0x9F },

    // More Latin characters and symbols (0xA0-0xAF)
    .{ "á", 0xA0 },  .{ "í", 0xA1 },  .{ "ó", 0xA2 },  .{ "ú", 0xA3 },
    .{ "ñ", 0xA4 },  .{ "Ñ", 0xA5 },  .{ "ª", 0xA6 },  .{ "º", 0xA7 },
    .{ "¿", 0xA8 },  .{ "⌐", 0xA9 }, .{ "¬", 0xAA },  .{ "½", 0xAB },
    .{ "¼", 0xAC },  .{ "¡", 0xAD },  .{ "«", 0xAE },  .{ "»", 0xAF },

    // Box drawing characters (0xB0-0xDF)
    .{ "░", 0xB0 }, .{ "▒", 0xB1 }, .{ "▓", 0xB2 }, .{ "│", 0xB3 },
    .{ "┤", 0xB4 }, .{ "╡", 0xB5 }, .{ "╢", 0xB6 }, .{ "╖", 0xB7 },
    .{ "╕", 0xB8 }, .{ "╣", 0xB9 }, .{ "║", 0xBA }, .{ "╗", 0xBB },
    .{ "╝", 0xBC }, .{ "╜", 0xBD }, .{ "╛", 0xBE }, .{ "┐", 0xBF },
    .{ "└", 0xC0 }, .{ "┴", 0xC1 }, .{ "┬", 0xC2 }, .{ "├", 0xC3 },
    .{ "─", 0xC4 }, .{ "┼", 0xC5 }, .{ "╞", 0xC6 }, .{ "╟", 0xC7 },
    .{ "╚", 0xC8 }, .{ "╔", 0xC9 }, .{ "╩", 0xCA }, .{ "╦", 0xCB },
    .{ "╠", 0xCC }, .{ "═", 0xCD }, .{ "╬", 0xCE }, .{ "╧", 0xCF },
    .{ "╨", 0xD0 }, .{ "╤", 0xD1 }, .{ "╥", 0xD2 }, .{ "╙", 0xD3 },
    .{ "╘", 0xD4 }, .{ "╒", 0xD5 }, .{ "╓", 0xD6 }, .{ "╫", 0xD7 },
    .{ "╪", 0xD8 }, .{ "┘", 0xD9 }, .{ "┌", 0xDA }, .{ "█", 0xDB },
    .{ "▄", 0xDC }, .{ "▌", 0xDD }, .{ "▐", 0xDE }, .{ "▀", 0xDF },

    // Greek letters and symbols (0xE0-0xFF)
    .{ "α", 0xE0 },  .{ "ß", 0xE1 },  .{ "Γ", 0xE2 },  .{ "π", 0xE3 },
    .{ "Σ", 0xE4 },  .{ "σ", 0xE5 },  .{ "µ", 0xE6 },  .{ "τ", 0xE7 },
    .{ "Φ", 0xE8 },  .{ "Θ", 0xE9 },  .{ "Ω", 0xEA },  .{ "δ", 0xEB },
    .{ "∞", 0xEC }, .{ "φ", 0xED },  .{ "ε", 0xEE },  .{ "∩", 0xEF },
    .{ "≡", 0xF0 }, .{ "±", 0xF1 },  .{ "≥", 0xF2 }, .{ "≤", 0xF3 },
    .{ "⌠", 0xF4 }, .{ "⌡", 0xF5 }, .{ "÷", 0xF6 },  .{ "≈", 0xF7 },
    .{ "°", 0xF8 },  .{ "∙", 0xF9 }, .{ "·", 0xFA },  .{ "√", 0xFB },
    .{ "ⁿ", 0xFC }, .{ "²", 0xFD }, .{ "■", 0xFE }, .{ " ", 0xFF }, // NBSP
});

pub const Utf8ToCp437Iterator = struct {
    bytes: []const u8,
    index: usize = 0,

    pub fn next(self: *@This()) ?u8 {
        if (self.index >= self.bytes.len) return null;

        // If it's ASCII, pass it directly
        if (self.bytes[self.index] < 0x80) {
            const result = self.bytes[self.index];
            self.index += 1;
            return result;
        }

        // Use std.unicode to decode UTF-8
        const utf8_view = std.unicode.Utf8View.init(self.bytes[self.index..]) catch {
            // If invalid, return the current byte
            defer self.index += 1;
            return self.bytes[self.index];
        };

        var iter = utf8_view.iterator();
        if (iter.nextCodepointSlice()) |utf8_slice| {
            // Advance index by the length of the UTF-8 sequence
            self.index += utf8_slice.len;

            // Search in the mapping table using the slice directly
            if (unicode_to_cp437.get(utf8_slice)) |cp437_code| {
                return cp437_code;
            }

            // If not found, check if it's a single-byte character in extended ASCII range
            if (utf8_slice.len == 1 and utf8_slice[0] < 0x80) {
                return utf8_slice[0];
            }

            // For multi-byte sequences, try to get the codepoint to check if it's < 256
            if (std.unicode.utf8Decode(utf8_slice)) |codepoint| {
                if (codepoint < 256) {
                    return @intCast(codepoint);
                }
            } else |_| {}

            return '?'; // Unsupported character
        }

        self.index += 1;
        return '?';
    }
};
