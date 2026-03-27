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

/// Coerce an Object to an integer value.
/// Returns 0 for non-integer types (simplified implicit conversion, §19.3.5).
pub fn to_int(obj: Object) u64 {
    return switch (obj) {
        .integer => |v| v,
        else => 0,
    };
}
