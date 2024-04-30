const ft = @import("../../ft/ft.zig");
const tty = @import("../../tty/tty.zig");
const multiboot = @import("../../multiboot.zig");
const multiboot2_h = @import("../../c_headers.zig").multiboot2_h;
const cpu = @import("../../cpu.zig");
const pit = @import("../pit/pit.zig");
const colors = @import("colors");

const acpi_logger = @import("../../ft/ft.zig").log.scoped(.driver_acpi);

const ACPI = @import("types/acpi.zig").ACPI;
const S5Object = @import("types/s5.zig").S5Object;

pub const RSDT = _entry_type("RSDT");
pub const DSDT = _entry_type("DSDT");

pub const ACPI_error = error{
    entry_not_found,
    entry_invalid,
    no_smi_command_port,
    no_known_enable_method,
    enable_failed,
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

var acpi: ACPI = .{};

fn _is_enabled(control_block: enum { pm1a, pm1b }) bool {
    return switch (control_block) {
        .pm1a => (cpu.inw(acpi.fadt.pm1a_control_block) & acpi.SCI_EN) != 0,
        .pm1b => (cpu.inw(acpi.fadt.pm1b_control_block) & acpi.SCI_EN) != 0,
    };
}

fn _entry_type(comptime name: []const u8) type {
    const names = .{ "RSDT", "FACP", "DSDT" };
    var index: ?usize = null;

    for (names, 0..) |n, i| if (ft.mem.eql(u8, n, name)) {
        index = i;
    };

    if (index) |i| {
        const array = [_]type{
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
        const ret = extern struct {
            header: ACPISDT_Header,
        };
        var tmp = @typeInfo(ret);
        tmp.Struct.fields = @typeInfo(ret).Struct.fields ++ @typeInfo(array[i]).Struct.fields;
        return @Type(tmp);
    } else @compileError("ACPI: Unknown entry type: '" ++ name ++ "'");
}

fn PTRI(comptime T: anytype) type {
    return [*]align(1) T;
}

fn PTR(comptime T: anytype) type {
    return *align(1) T;
}

pub fn acpi_strerror(comptime name: []const u8, err: ACPI_error) []const u8 {
    return switch (err) {
        ACPI_error.entry_not_found => "ACPI: " ++ name ++ " not found",
        ACPI_error.entry_invalid => "ACPI: Failed to validate " ++ name ++ " (invalid checksum)",
        ACPI_error.no_smi_command_port => "ACPI: No SMI command port found",
        ACPI_error.no_known_enable_method => "ACPI: No known enable method",
        ACPI_error.enable_failed => "ACPI: Failed to enable",
    };
}

fn _checksum(rsdp: anytype, size: usize) bool {
    const ptr: PTRI(u8) = @ptrFromInt(@intFromPtr(rsdp));
    var sum: u8 = 0;

    for (0..size) |p| sum +%= ptr[p];
    return sum == 0;
}

fn _validate(comptime T: type, comptime name: []const u8, entry: anytype) ACPI_error!PTR(T) {
    const len = if (@hasField(@TypeOf(entry.*), "header")) entry.header.length else @sizeOf(@TypeOf(entry.*));

    return if (_checksum(entry, len)) b: {
        acpi_logger.debug("{s}: checksum:\t{s}OK{s}\t({s}0x{x:0>8}{s})\t{s}{d}{s} bytes", .{
            colors.magenta ++ name ++ colors.reset,
            colors.green,
            colors.reset,
            colors.blue,
            @intFromPtr(entry),
            colors.reset,
            colors.yellow,
            len,
            colors.reset,
        });
        break :b @as(PTR(T), @ptrFromInt(@intFromPtr(entry)));
    } else b: {
        acpi_logger.err("{s} checksum:\t{s}KO{s}\t({s}0x{x:0>8}{s})", .{
            colors.magenta ++ name ++ colors.reset,
            colors.red,
            colors.reset,
            colors.blue,
            @intFromPtr(entry),
            colors.reset,
        });
        break :b ACPI_error.entry_invalid;
    };
}

fn _find_entry(rsdt: PTR(RSDT), comptime name: []const u8) ACPI_error!PTR(_entry_type(name)) {
    const entries = (rsdt.header.length - @sizeOf(ACPISDT_Header)) / @sizeOf(usize);

    const entry_addr: PTRI(usize) = @ptrFromInt(@intFromPtr(&rsdt.pointer_to_other_sdt));
    for (entry_addr[0..entries]) |entry| {
        const header: PTR(ACPISDT_Header) = map(ACPISDT_Header, entry);

        if (ft.mem.eql(u8, &header.signature, name)) {
            acpi_logger.debug("{s}: Search:\t{s}OK{s}\t({s}0x{x:0>8}{s})", .{
                colors.magenta ++ name ++ colors.reset,
                colors.green,
                colors.reset,
                colors.blue,
                @intFromPtr(header),
                colors.reset,
            });
            return _validate(_entry_type(name), name, @as(PTR(_entry_type(name)), @ptrCast(header)));
        } else unmap(header, header.length) catch acpi_logger.warn(
            "Failed to unmap {s} object",
            .{header.signature},
        );
    }
    acpi_logger.err(
        "{s}: Search:\t{s}KO{s}",
        .{ colors.magenta ++ name ++ colors.reset, colors.red, colors.reset },
    );
    return ACPI_error.entry_not_found;
}

fn _get_rsdp() ACPI_error!PTR(RSDP) {
    var rsdp: PTR(RSDP) = undefined;

    acpi_logger.debug("{s}RSDP{s}: Retrieving from mutliboot2 header", .{ colors.magenta, colors.reset });
    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ACPI_OLD)) |tag| {
        acpi_logger.debug("\t- Found ACPI_OLD tag", .{});
        rsdp = &tag.rsdp;
    } else if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ACPI_NEW)) |tag| {
        acpi_logger.debug("\t- Found ACPI_NEW tag", .{});
        rsdp = &tag.rsdp;
    } else return ACPI_error.entry_not_found;

    rsdp = _validate(RSDP, "RSDP", rsdp) catch |err| return err;

    acpi_logger.debug(
        "\t- oem: {s}\n\t\t\t\t\t\t- revision: {d}\n\t\t\t\t\t\t- rsdt: 0x{x}",
        .{ rsdp.oemid, rsdp.revision, @intFromPtr(rsdp.rsdt_address) },
    );
    return rsdp;
}

fn _get_rsdt(rsdp: PTR(RSDP)) ACPI_error!PTR(RSDT) {
    return _validate(RSDT, "RSDT", map(RSDT, @intFromPtr(rsdp.rsdt_address)));
}

fn _get_dsdt(facp: PTR(_entry_type("FACP"))) ACPI_error!PTR(DSDT) {
    return _validate(DSDT, "DSDT", map(DSDT, facp.fadt.dsdt));
}

fn _get_s5(dsdt: PTR(DSDT)) ACPI_error!PTR(S5Object) {
    const data: PTRI(u8) = @ptrFromInt(@as(usize, @intFromPtr(&dsdt.data)));

    for (0..dsdt.header.length) |i| {
        if (ft.mem.eql(u8, data[i .. i + 5], "_S5_\x12")) {
            if (!(data[i - 1] == 0x08 or (data[i - 1] == 0x5C and data[i - 2] == 0x08))) continue;

            acpi_logger.debug(
                "{s}:\tSearch\t\t{s}OK{s}\t({s}0x{x:0>8}{s})",
                .{
                    colors.magenta ++ "_S5" ++ colors.reset,
                    colors.green,
                    colors.reset,
                    colors.blue,
                    @intFromPtr(data) + i,
                    colors.reset,
                },
            );
            const s5: PTR(S5Object) = @ptrFromInt(@as(usize, @intFromPtr(&dsdt.data)) + i + 4);
            acpi_logger.debug(
                "{s}:\t0x{x:0>14}",
                .{ colors.magenta ++ "_S5" ++ colors.reset, @as(u56, @bitCast(s5.*)) },
            );
            return s5;
        }
    }
    acpi_logger.err(
        "{s}:\tSearch\t\t{s}KO{s}",
        .{ colors.magenta ++ "_S5" ++ colors.reset, colors.red, colors.reset },
    );
    return ACPI_error.entry_not_found;
}

pub fn power_off() void {
    cpu.outw(acpi.fadt.pm1a_control_block, acpi.SLP_TYPa | acpi.SLP_EN);
}

pub fn enable() ACPI_error!void {
    acpi_logger.debug("Enabling...", .{});
    if (_is_enabled(.pm1a)) {
        acpi_logger.debug("Already enabled", .{});
        return;
    }
    if (acpi.fadt.smi_command_port == 0) {
        acpi_logger.err("No SMI command port found", .{});
        return ACPI_error.no_smi_command_port;
    }
    if (acpi.fadt.acpi_enable == 0) {
        acpi_logger.err("No known enable method", .{});
        return ACPI_error.no_known_enable_method;
    }

    acpi_logger.debug("\t- send acpi enable command to SMI command port", .{});
    cpu.outb(acpi.fadt.smi_command_port, acpi.fadt.acpi_enable);

    acpi_logger.debug("\t- waiting for enable", .{});
    var time: u32 = 0;
    const interval: u32 = 10; // interval between checks in ms
    while (time < acpi.TIMEOUT) : (time += interval) {
        pit.sleep(interval);
        if (_is_enabled(.pm1a)) break;
    }
    if (acpi.fadt.pm1b_control_block != 0) {
        while (time < acpi.TIMEOUT) : (time += interval) {
            pit.sleep(interval);
            if (_is_enabled(.pm1b)) break;
        }
    }
    if (time >= acpi.TIMEOUT) {
        acpi_logger.err("Failed to enable", .{});
        return ACPI_error.enable_failed;
    }
    acpi_logger.debug("\t- Done ({d} ms)", .{time});
}

pub fn init() void {
    const rsdp = _get_rsdp() catch |err| @panic(acpi_strerror("RSDP", err));
    const rsdt = _get_rsdt(rsdp) catch |err| @panic(acpi_strerror("RSDT", err));
    const facp = _find_entry(rsdt, "FACP") catch |err| @panic(
        acpi_strerror("FACP", err),
    );
    const dsdt = _get_dsdt(facp) catch |err| @panic(acpi_strerror("DSDT", err));
    const s5 = _get_s5(dsdt) catch |err| @panic(acpi_strerror("_S5", err));

    acpi.fadt = &facp.fadt;

    // TODO: Add a way to ignore the line width check for the following line in CI..
    // https://uefi.org/htmlspecs/ACPI_Spec_6_4_html/04_ACPI_Hardware_Specification/
    // ...ACPI_Hardware_Specification.html#pm1-control-registers-2
    acpi.SLP_TYPa = @as(u16, s5.slp_typ_a_num) << 10;
    acpi.SLP_TYPb = @as(u16, s5.slp_typ_b_num) << 10;
    acpi.SLP_EN = 1 << 13;
    acpi.SCI_EN = 1;

    acpi_logger.debug("\t- (SLP_TYPa | SLP_EN): 0x{x}", .{acpi.SLP_TYPa | acpi.SLP_EN});
    acpi_logger.debug("\t- (PM1a_CNT): 0x{x}", .{acpi.fadt.pm1a_control_block});
    acpi_logger.debug("Initialization:\t" ++ colors.green ++ "OK" ++ colors.reset, .{});

    enable() catch |err| @panic(acpi_strerror("", err));
    acpi_logger.info("Enabled", .{});
}

const paging = @import("../../memory/paging.zig");

fn map(comptime T: type, ptr: paging.PhysicalPtr) PTR(T) {
    const memory = @import("../../memory.zig");

    const object: PTR(T) = @ptrCast(
        @alignCast(memory.kernel_virtual_space.map_object_anywhere(
            ptr,
            @sizeOf(T),
        ) catch @panic("can't map acpi object")),
    );

    const len = if (@hasField(
        T,
        "header",
    )) object.header.length else if (@hasField(
        T,
        "length",
    )) object.length else return object;

    defer unmap(object, @sizeOf(T)) catch |e| acpi_logger.warn(
        "Failed to unmap {s}: {s}",
        .{ @typeName(T), @errorName(e) },
    );

    return @ptrCast(
        @alignCast(memory.kernel_virtual_space.map_object_anywhere(
            ptr,
            len,
        ) catch @panic("can't map acpi object")),
    );
}

fn unmap(ptr: anytype, len: usize) !void {
    const memory = @import("../../memory.zig");
    try memory.kernel_virtual_space.unmap_object(@ptrCast(ptr), len);
}
