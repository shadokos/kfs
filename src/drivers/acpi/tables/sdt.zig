const std = @import("std");
const colors = @import("colors");
const log = std.log.scoped(.@"acpi(sdth)");

/// Common ACPI System Description Table header (36 bytes).
/// Defined in ACPI 6.4 §5.2.6 (System Description Table Header).
/// Shared by RSDT, FADT (FACP), DSDT, SSDT, MADT, HPET, MCFG, etc.
pub const SdtHeader = extern struct {
    signature: [4]u8,
    length: u32,
    revision: u8,
    checksum: u8,
    oem_id: [6]u8,
    oem_table_id: [8]u8,
    oem_revision: u32,
    creator_id: u32,
    creator_revision: u32,

    /// Returns the raw data bytes following the header.
    pub fn data(self: *align(1) const SdtHeader) [*]align(1) const u8 {
        return @ptrFromInt(@intFromPtr(self) + @sizeOf(SdtHeader));
    }

    /// Returns the size of the data region (total length minus header).
    pub fn data_len(self: *align(1) const SdtHeader) u32 {
        return self.length -| @sizeOf(SdtHeader);
    }

    /// Validate the table checksum (sum of all bytes must be 0).
    pub fn validate(self: *align(1) const SdtHeader) bool {
        const valid = checksum(@ptrCast(self), self.length);
        if (valid) {
            log.debug("checksum({s}): OK (0x{x:0>8}, len {d})", .{ self.signature, @intFromPtr(self), self.length });
        } else {
            log.err("checksum({s}): KO (0x{x:0>8}, len {d})", .{ self.signature, @intFromPtr(self), self.length });
        }
        return valid;
    }
};

/// Generic checksum over a byte range. Returns true if sum == 0.
pub fn checksum(ptr: [*]align(1) const u8, len: u32) bool {
    var sum: u8 = 0;
    for (0..len) |i| sum +%= ptr[i];
    return sum == 0;
}
