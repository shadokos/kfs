const ft = @import("../../ft/ft.zig");
const tty = @import("../../tty/tty.zig");
const utils = @import("../../shell/utils.zig");
const multiboot = @import("../../multiboot.zig");
const multiboot2_h = @import("../../c_headers.zig").multiboot2_h;
const ports = @import("../../io/ports.zig");

const ACPI = @import("types/acpi.zig").ACPI;
const S5Object = @import("types/s5.zig").S5Object;

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

var acpi : ACPI = .{};

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
		extern struct {
			data: u8,
		}, // DSDT
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

	return if (_checksum(entry, len)) b: {
		tty.printk("ACPI: {s}: checksum:\t{s}OK{s}\n", .{
			utils.magenta++name++utils.reset, utils.green, utils.reset
		});
		break :b @as(PTR(T), @ptrFromInt(@intFromPtr(entry)));
	} else ACPI_error.entry_invalid;
}

fn _find_entry(rsdt: PTR(RSDT), comptime name: *const [4]u8) ACPI_error!PTR(entry_type(name)) {
	const entries = (rsdt.header.length - @sizeOf(ACPISDT_Header)) / @sizeOf(usize);

	for (0..entries) |i| {
		const entry_addr: PTRI(usize) = @ptrFromInt(@intFromPtr(&rsdt.pointer_to_other_sdt));
		const entry = entry_addr[i];
		const header: PTR(ACPISDT_Header) = @ptrFromInt(entry);

		if (ft.mem.eql(u8, &header.signature, name)) {
			tty.printk("ACPI: {s}: Search:\t\t{s}OK{s}\t({s}0x{x}{s})\n", .{
				utils.magenta++name++utils.reset,
				utils.green, utils.reset,
				utils.blue, entry, utils.reset
			});

			return _validate(entry_type(name), name, @as(PTR(entry_type(name)), @ptrFromInt(entry)));
		}
	}
	return ACPI_error.entry_not_found;
}

fn _get_rsdp() ACPI_error!PTR(RSDP) {
	tty.printk("ACPI: {s}RSDP{s}: Retrieving from mutliboot2 header\n", .{
		utils.magenta, utils.reset
	});
	return if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ACPI_OLD)) |tag| {
		tty.printk("ACPI: {s}: Found tag\n", .{ utils.magenta++"ACPI_OLD"++utils.reset });
		return _validate(RSDP, "RSDP", &tag.rsdp);
	} else if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ACPI_NEW)) |tag| {
		tty.printk("ACPI: {s}: Found tag\n", .{ utils.magenta++"ACPI_NEW"++utils.reset });
		return _validate(RSDP, "RSDP", &tag.rsdp);
	} else ACPI_error.entry_not_found;
}

fn _get_rsdt(rsdp: PTR(RSDP)) ACPI_error!PTR(RSDT) {
	return _validate(RSDT, "RSDT", rsdp.rsdt_address);
}

fn _get_dsdt(facp: PTR(entry_type("FACP"))) ACPI_error!PTR(DSDT) {
	return _validate(DSDT, "DSDT", @as(PTR(DSDT), @ptrFromInt(facp.fadt.dsdt)));
}

pub fn init() u32 {
	const rsdp = _get_rsdp() catch |err| @panic(acpi_strerror("RSDP", err));
	const rsdt = _get_rsdt(rsdp) catch |err| @panic(acpi_strerror("RSDT", err));
	const facp = _find_entry(rsdt, "FACP") catch |err| @panic(acpi_strerror("FACP", err));
	const dsdt = _get_dsdt(facp) catch |err| @panic(acpi_strerror("DSDT", err));

	const data: PTRI(u8) = @ptrFromInt(@as(usize, @intFromPtr(&dsdt.data)));

	acpi.fadt = &facp.fadt;
	acpi.SMI_CMD = &facp.fadt.smi_command_port;
	acpi.PM1a_CNT = facp.fadt.pm1a_control_block;
	acpi.PM1b_CNT = facp.fadt.pm1b_control_block;
	acpi.ACPI_ENABLE = &facp.fadt.acpi_enable;
	acpi.ACPI_DISABLE = &facp.fadt.acpi_disable;
	acpi.PM1a_CNT = facp.fadt.pm1a_control_block;
	acpi.PM1b_CNT = facp.fadt.pm1b_control_block;
	acpi.PM1_CNT_LEN = facp.fadt.pm1_control_length;
	for (0..dsdt.header.length) |i| {
		if (ft.mem.eql(u8, data[i..i+5], "_S5_\x12")) {
			if (!(data[i-1] == 0x08 or (data[i-1] == 0x5A and data[i-2] == 0x08))) continue;

			tty.printk("ACPI: {s}:\tSearch\t\t{s}OK{s}\t({s}0x{x}{s})\n", .{
				utils.magenta++"_S5"++utils.reset,
				utils.green, utils.reset,
				utils.blue, @intFromPtr(data) + i, utils.reset
			});
			const s5: PTR(S5Object) = @ptrFromInt(@as(usize, @intFromPtr(&dsdt.data)) + i + 4);
			acpi.SLP_TYPa = @as(u16, s5.slp_typ_a_num) << 10;
			acpi.SLP_TYPb = @as(u16, s5.slp_typ_b_num) << 10;
		}
	}
	tty.printk("ACPI: PM1a_CNT: {s}0x{x}{s}, (SLP_TYPa | SLP_EN): {s}0x{x}{s}\n", .{
    	utils.blue, acpi.PM1a_CNT, utils.reset,
    	utils.blue, acpi.SLP_TYPa | acpi.SLP_EN, utils.reset
    });
    tty.printk("ACPI: Initiliazation:\t"++utils.green++"OK"++utils.reset++"\n", .{});
	return 0;
}

pub fn shutdown() bool {
	ports.outw(acpi.PM1a_CNT, acpi.SLP_TYPa | acpi.SLP_EN);
	return false;
}