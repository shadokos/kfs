/// RSDP (Root System Description Pointer) structure and related functions.
/// The RSDP is the entry point to the ACPI subsystem,
/// containing the physical address of the RSDT and basic information about the ACPI version.
/// We retrieve it from the multiboot2 tags and validate its checksum before using it to find the RSDT.
///
const std = @import("std");
const sdt = @import("sdt.zig");
const multiboot = @import("../../../multiboot.zig");
const multiboot2_h = @import("../../../c_headers.zig").multiboot2_h;

const log = std.log.scoped(.@"acpi(rsdp)");

pub const RSDP = extern struct {
    signature: [8]u8,
    checksum: u8,
    oem_id: [6]u8,
    revision: u8,
    rsdt_address: u32,
};

pub const Error = error{
    not_found,
    invalid_checksum,
};

pub const RsdpResult = struct {
    rsdt_address: u32,
    revision: u8,
    oem_id: [6]u8,
};

/// Retrieve and validate the RSDP from multiboot2 tags.
pub fn find_from_multiboot() Error!*const RSDP {
    log.debug("retrieving from multiboot2 header", .{});

    const rsdp: *const RSDP = blk: {
        if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ACPI_OLD)) |tag| {
            log.debug("found ACPI_OLD tag", .{});
            break :blk &tag.rsdp;
        } else if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ACPI_NEW)) |tag| {
            log.debug("found ACPI_NEW tag", .{});
            break :blk &tag.rsdp;
        } else {
            log.err("not found in multiboot2 tags", .{});
            return Error.not_found;
        }
    };

    // Validate RSDP v1 checksum (first 20 bytes)
    const valid = sdt.checksum(@ptrCast(rsdp), @sizeOf(RSDP));
    if (valid) {
        log.debug("checksum: OK (0x{x:0>8})", .{@intFromPtr(rsdp)});
    } else {
        log.err("checksum: KO (0x{x:0>8})", .{@intFromPtr(rsdp)});
        return Error.invalid_checksum;
    }

    log.debug("oem: {s}", .{rsdp.oem_id});
    log.debug("revision: {d}", .{rsdp.revision});
    log.debug("RSDT address: 0x{x:0>8}", .{rsdp.rsdt_address});

    return rsdp;
}
