/// AML integer constants and coercion helpers.
///
/// Integer data encodings (ACPI 6.4 §20.2.3):
///   ByteConst  := BytePrefix ByteData       (0x0A)
///   WordConst  := WordPrefix WordData        (0x0B)
///   DWordConst := DWordPrefix DWordData      (0x0C)
///   QWordConst := QWordPrefix QWordData      (0x0E)
///   ZeroOp     := 0x00
///   OneOp      := 0x01
///   OnesOp     := 0xFF
///
/// For ACPI rev 1, OnesOp yields 0xFFFFFFFF (32-bit) per §5.7.4.
const objects = @import("../objects.zig");

const Object = objects.Object;

/// Mask an integer result to 32 bits.
/// Required when \_REV = 1 (ACPI rev 1, 32-bit integer mode, §5.7.4).
pub inline fn mask32(v: u64) u64 {
    return v & 0xFFFFFFFF;
}

/// Coerce an Object to an integer value (§19.3.5, Table 19.7).
/// Integer → as-is.
/// String  → parse as decimal or hex ("0x" prefix). Returns 0 on failure.
/// Buffer  → interpret up to first 4 bytes as little-endian u32 (32-bit mode).
/// Others  → 0.
pub fn to_int(obj: Object) u64 {
    return switch (obj) {
        .integer => |v| v,
        .string => |s| parse_string_int(s),
        .buffer => |b| buf_to_int(b.data),
        else => 0,
    };
}

/// Parse a string as an integer: "0x..." for hex, otherwise decimal (§19.3.5).
fn parse_string_int(s: []const u8) u64 {
    if (s.len == 0) return 0;

    // Skip leading whitespace
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t')) : (i += 1) {}
    if (i >= s.len) return 0;

    // Hex prefix "0x" or "0X"
    if (i + 1 < s.len and s[i] == '0' and (s[i + 1] == 'x' or s[i + 1] == 'X')) {
        i += 2;
        var val: u64 = 0;
        while (i < s.len) : (i += 1) {
            const c = s[i];
            const digit: u64 = if (c >= '0' and c <= '9')
                c - '0'
            else if (c >= 'A' and c <= 'F')
                c - 'A' + 10
            else if (c >= 'a' and c <= 'f')
                c - 'a' + 10
            else
                break;
            val = (val << 4) | digit;
        }
        return mask32(val);
    }

    // Decimal
    var val: u64 = 0;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
        val = val * 10 + (s[i] - '0');
    }
    return mask32(val);
}

/// Interpret buffer bytes as a little-endian integer (§19.3.5, 32-bit mode: up to 4 bytes).
fn buf_to_int(data: []const u8) u64 {
    var val: u64 = 0;
    const len = if (data.len < 4) data.len else 4;
    for (0..len) |i| {
        val |= @as(u64, data[i]) << @intCast(i * 8);
    }
    return val;
}
