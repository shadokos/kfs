const ft = @import("../../ft/ft.zig");
const tty = @import("../../tty/tty.zig");
const utils = @import("../../shell/utils.zig");
const multiboot = @import("../../multiboot.zig");
const multiboot2_h = @import("../../c_headers.zig").multiboot2_h;

pub const RSDT = entry_type("RSDT");
pub const DSDT = entry_type("DSDT");

pub const ACPI_error = error{
	entry_not_found,
	entry_invalid,
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

fn entry_type(comptime name: *const [4]u8) type {
	const names = .{ "RSDT", "FACP", "DSDT" };
	var index: ?usize = null;

	for (names, 0..) |n, i| if (ft.mem.eql(u8, n, name)) { index = i; };

	if (index == null) @compileError("ACPI: Unknown entry type: '" ++ name ++ "'");

	const array = [_]type {
		extern struct { // RSDT
			pointer_to_other_sdt: usize,
		},
		extern struct { // FACP
			fadt: @import("types/fadt.zig").FADT,
		},
		extern struct {}, // DSDT
	};
	var ret = struct {
		header: ACPISDT_Header,
	};
	var tmp = @typeInfo(ret);
	tmp.Struct.fields = @typeInfo(ret).Struct.fields ++ @typeInfo(array[index.?]).Struct.fields;
	return @Type(tmp);
}

fn PTRI(comptime T: anytype) type {
	return [*]align(1) T;
}

fn PTR(comptime T: anytype) type {
	return *align(1) T;
}

inline fn acpi_strerror(comptime name: *const [4]u8, err: ACPI_error) []const u8 {
	return switch (err) {
		ACPI_error.entry_not_found => "ACPI: " ++ name ++ " not found",
		ACPI_error.entry_invalid => "ACPI: Failed to validate " ++ name ++ " (invalid checksum)",
		else => unreachable,
	};
}

fn _checksum(rsdp: anytype, size: usize) bool {
	const ptr: PTRI(u8) = @ptrFromInt(@intFromPtr(rsdp));
	var sum: u8 = 0;

	for (0..size) |p| sum +%= ptr[p];
	return sum == 0;
}

fn _validate(comptime T: type, comptime name: *const [4]u8, entry: anytype) ACPI_error!PTR(T) {
	const len = if (@hasField(@TypeOf(entry.*), "header")) entry.header.length
				else @sizeOf(@TypeOf(entry.*));

	tty.printk("ACPI: Validating {s}"++name++"{s} ({s}0x{x}:{d} bytes{s})\n", .{
		utils.magenta, utils.reset, utils.blue, @intFromPtr(entry), len, utils.reset,
	});
	return if (_checksum(entry, len)) b: {
		tty.printk("ACPI: "++name++" checksum: {s}OK{s}\n", .{
			utils.green, utils.reset
		});
		break :b @as(PTR(T), @ptrFromInt(@intFromPtr(entry)));
	} else ACPI_error.entry_invalid;
}

fn _find_entry(rsdt: PTR(RSDT), comptime name: *const [4]u8) ACPI_error!PTR(entry_type(name)) {
	const entries = (rsdt.header.length - @sizeOf(ACPISDT_Header)) / @sizeOf(usize);

	tty.printk("ACPI: Searching for entry {s} ({s}0x{x}:{d} entries{s})\n", .{
		utils.magenta++name++utils.reset,
		utils.blue, @intFromPtr(&rsdt.pointer_to_other_sdt),
		entries, utils.reset
	});

	for (0..entries) |i| {
		const entry_addr: PTRI(usize) = @ptrFromInt(@intFromPtr(&rsdt.pointer_to_other_sdt));
		const entry = entry_addr[i];
		const header: PTR(ACPISDT_Header) = @ptrFromInt(entry);

		if (ft.mem.eql(u8, &header.signature, name)) {
			tty.printk("ACPI: Found entry {s} at {s}0x{x}{s}\n", .{
				utils.magenta++name++utils.reset,
				utils.blue, entry, utils.reset
			});

			return _validate(entry_type(name), name, @as(PTR(entry_type(name)), @ptrFromInt(entry)));
		}
	}
	return ACPI_error.entry_not_found;
}

fn _get_rsdp() ACPI_error!PTR(RSDP) {
	tty.printk("ACPI: Retrieving {s}RSDP{s} from mutliboot2 header\n", .{
		utils.magenta, utils.reset
	});
	return if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ACPI_OLD)) |tag| {
		return _validate(RSDP, "RSDP", &tag.rsdp);
	} else ACPI_error.entry_not_found;
}

fn _get_rsdt(rsdp: PTR(RSDP)) ACPI_error!PTR(RSDT) {
	return _validate(RSDT, "RSDT", rsdp.rsdt_address);
}

fn _get_dsdt(facp: PTR(entry_type("FACP"))) ACPI_error!PTR(DSDT) {
	return _validate(DSDT, "DSDT", @as(PTR(DSDT), @ptrFromInt(facp.fadt.dsdt)));
}

pub fn enable() u32 {
	const rsdp = _get_rsdp() catch |err| @panic(acpi_strerror("RSDP", err));
	const rsdt = _get_rsdt(rsdp) catch |err| @panic(acpi_strerror("RSDT", err));
	const facp = _find_entry(rsdt, "FACP") catch |err| @panic(acpi_strerror("FACP", err));
	const dsdt = _get_dsdt(facp) catch |err| @panic(acpi_strerror("DSDT", err));

	_ = dsdt;
	return 0;
}
