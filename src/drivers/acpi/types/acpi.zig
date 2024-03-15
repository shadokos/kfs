const FADT = @import("fadt.zig").FADT;

fn PTR(comptime T: type) type {
    return *align(1) T;
}

pub const ACPI = extern struct {
    fadt: PTR(FADT) = undefined,
    SLP_TYPa: u16 = 0,
    SLP_TYPb: u16 = 0,
    SLP_EN: u16 = 1 << 13,
    SCI_EN: u16 = 0,
    TIMEOUT: usize = 100000000,
};
