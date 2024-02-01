const ft = @import("../ft/ft.zig");
const tty = @import("../tty/tty.zig");
const utils = @import("../shell/utils.zig");

const multiboot = @import("../multiboot.zig");
const multiboot2_h = @import("../c_headers.zig").multiboot2_h;

pub const ACPI_error = error {
	rsdp_not_found,
	rsdp_invalid,
};

pub const RSDP = extern struct {
	signature: [8]u8,
	checksum: u8,
	oemid: [6]u8,
	revision: u8,
	rsdt_address: usize,
};

fn _validate_rsdp(rsdp: RSDP) bool {
	tty.printk("ACPI: Validating rsdp\n", .{});

	const raw_bytes = @as([@sizeOf(RSDP)]u8, @bitCast(rsdp));
	var sum: u8 = 0;

    for (raw_bytes) |p| sum +%= p;
    return sum == 0;
}

fn _get_rsdp() ACPI_error!RSDP {
	tty.printk("ACPI: Retrieving RSDP from mutliboot2 header\n", .{});

	return if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ACPI_OLD)) |tag| b: {
		break :b
			if (_validate_rsdp(tag.rsdp)) tag.rsdp
			else ACPI_error.rsdp_invalid;
	}
	else ACPI_error.rsdp_not_found;
}

pub fn enable() u32 {
	const rsdp: RSDP = _get_rsdp() catch |err| switch (err) {
		ACPI_error.rsdp_not_found => @panic("ACPI: no rsdp found"),
		ACPI_error.rsdp_invalid => @panic("ACPI: Failed to validate rsdp (invalid checksum)")
	};

	tty.printk("ACPI: rsdp found at 0x{x}\n", .{rsdp.rsdt_address});
	return 0;
}