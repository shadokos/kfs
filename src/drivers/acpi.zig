const ft = @import("../ft/ft.zig");
const tty = @import("../tty/tty.zig");
const utils = @import("../shell/utils.zig");

const multiboot = @import("../multiboot.zig");
const multiboot2_h = @import("../c_headers.zig").multiboot2_h;

pub const ACPI_error = error {
	rsdp_not_found,
	rsdp_invalid,
	rsdt_not_found,
	rsdt_invalid,
};

pub const RSDP = extern struct {
	signature: [8]u8,
	checksum: u8,
	oemid: [6]u8,
	revision: u8,
	rsdt_address: *RSDT,
};

pub const ACPISDT_Header = extern struct {
	signature: [4]u8,
	length: u32,
	revision: u8,
	checksum: u8,
	oemid: [6]u8,
	oem_table_id: [8]u8,
	oem_revision: u32,
	creator_id: u32,
	creator_revision: u32,
};

pub const RSDT = extern struct {
	header: ACPISDT_Header,
	entries: [*]usize,
};

fn _checksum(rsdp: anytype, size: usize) bool {
	const ptr : [*] align(1) u8 = @as([*]u8, @ptrFromInt(@intFromPtr(rsdp)));
	var sum: u8 = 0;

    for (0..size) |p| sum +%= ptr[p];
    return sum == 0;
}

fn _get_rsdp() ACPI_error!RSDP {
	tty.printk("ACPI: Retrieving rsdp from mutliboot2 header\n", .{});
	return if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ACPI_OLD)) |tag| b: {
		tty.printk("ACPI: Validating rsdp\n", .{});
		if (_checksum(&tag.rsdp, @sizeOf(RSDP))) {
			tty.printk("ACPI: rsdp checksum is valid\n", .{});
			break :b tag.rsdp;
		}
		else break :b ACPI_error.rsdp_invalid;
	}
	else ACPI_error.rsdp_not_found;
}

fn _get_rsdt(rsdp: RSDP) ACPI_error!*RSDT {
	tty.printk("ACPI: Validating rsdt (0x{x}) for {d} entries\n", .{
		@intFromPtr(rsdp.rsdt_address), rsdp.rsdt_address.header.length,
	});
	return if (_checksum(rsdp.rsdt_address, rsdp.rsdt_address.header.length)) b: {
		tty.printk("ACPI: rsdt checksum is valid\n", .{});
		break :b rsdp.rsdt_address;
	}
	else ACPI_error.rsdt_invalid;
}

pub fn enable() u32 {
	const rsdp: RSDP = _get_rsdp() catch |err| switch (err) {
		ACPI_error.rsdp_not_found => @panic("ACPI: no rsdp found"),
		ACPI_error.rsdp_invalid => @panic("ACPI: Failed to validate rsdp (invalid checksum)"),
		else => unreachable,
	};

	const rsdt = _get_rsdt(rsdp) catch |err| switch (err) {
		ACPI_error.rsdt_not_found => @panic("ACPI: no rsdt found"),
		ACPI_error.rsdt_invalid => @panic("ACPI: Failed to validate rsdt (invalid checksum)"),
		else => unreachable,
	};
	_ = rsdt;
	return 0;
}