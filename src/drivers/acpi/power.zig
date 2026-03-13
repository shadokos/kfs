const std = @import("std");
const Acpi = @import("acpi.zig");
const osl = @import("os_layer.zig");
const FADT = @import("tables/fadt.zig").FADT;
const sdt = @import("tables/sdt.zig");

const log = std.log.scoped(.@"acpi(power)");

/// PM1 Control Register (PM1a_CNT / PM1b_CNT, ACPI 6.5 spec §4.8.3.2.1)
/// https://uefi.org/specs/ACPI/6.5/04_ACPI_Hardware_Specification.html#pm1-control-registers-2
pub const Pm1Control = packed struct(u16) {
    sci_en: bool, // bit 0: SCI enable (read-only on HW-reduced)
    bm_rld: bool, // bit 1: bus master reload
    gbl_rls: bool, // bit 2: global release
    _reserved1: u6 = 0, // bits 3-8
    _ignored: u1 = 0, // bit 9
    slp_typ: u3, // bits 10-12: sleep type (from \_Sx)
    slp_en: bool, // bit 13: sleep enable (write-only)
    _reserved2: u2 = 0, // bits 14-15
};

pub const Error = error{
    no_smi_command_port,
    no_known_enable_method,
    enable_timeout,
    no_fadt,
    s5_not_found,
};

const ENABLE_TIMEOUT_MS: u32 = 5000;
const POLL_INTERVAL_MS: u32 = 10;

/// Cached sleep type values extracted from DSDT \_Sx objects.
var slp_typ_a: u3 = 0;
var slp_typ_b: u3 = 0;
var s5_initialized: bool = false;

/// Enable ACPI mode by sending the enable command to the SMI command port.
pub fn enable_acpi() Error!void {
    const fadt = Acpi.get_fadt() orelse return Error.no_fadt;

    log.debug("Enabling ACPI...", .{});

    if (is_enabled(fadt)) {
        log.debug("Already enabled", .{});
        return;
    }

    if (fadt.smi_command_port == 0) {
        log.err("No SMI command port found", .{});
        return Error.no_smi_command_port;
    }
    if (fadt.acpi_enable == 0) {
        log.err("No known enable method", .{});
        return Error.no_known_enable_method;
    }

    log.debug("- send acpi enable command to SMI command port", .{});
    osl.write_io(@truncate(fadt.smi_command_port), 1, fadt.acpi_enable);

    log.debug("- waiting for enable", .{});
    var time: u32 = 0;
    while (time < ENABLE_TIMEOUT_MS) : (time += POLL_INTERVAL_MS) {
        osl.stall_ms(POLL_INTERVAL_MS);
        if (is_enabled(fadt)) break;
    }

    if (fadt.pm1b_control_block != 0) {
        while (time < ENABLE_TIMEOUT_MS) : (time += POLL_INTERVAL_MS) {
            osl.stall_ms(POLL_INTERVAL_MS);
            if (is_pm1b_enabled(fadt)) break;
        }
    }

    if (time >= ENABLE_TIMEOUT_MS) {
        log.err("Failed to enable (timeout after {d}ms)", .{ENABLE_TIMEOUT_MS});
        return Error.enable_timeout;
    }

    log.debug("- Done ({d} ms)", .{time});
}

/// Initialize S5 sleep type values by parsing the \_S5_ object from the DSDT.
/// This uses raw bytecode pattern matching as a fallback until the AML interpreter
/// is available, at which point this will be replaced by evaluate("\_S5_").
pub fn init_s5_from_dsdt(dsdt_data: []const u8) Error!void {
    // Search for _S5_ NameOp pattern in DSDT bytecode:
    //   NameOp(0x08) [RootPrefix(0x5C)] '_S5_' PackageOp(0x12)
    for (0..dsdt_data.len -| 5) |i| {
        if (!std.mem.eql(u8, dsdt_data[i..][0..5], "_S5_\x12")) continue;

        // Verify NameOp precedes the name
        if (i < 1) continue;
        const has_nameop = dsdt_data[i - 1] == 0x08 or
            (i >= 2 and dsdt_data[i - 2] == 0x08 and dsdt_data[i - 1] == 0x5C);
        if (!has_nameop) continue;

        // Parse the Package after "_S5_"
        // Skip: PackageOp(1) + PkgLength(1) + NumElements(1) = 3 bytes
        const pkg_start = i + 4; // points to PackageOp
        if (pkg_start + 3 >= dsdt_data.len) continue;

        // after PackageOp + PkgLength + NumElements
        const pkg_data = dsdt_data[pkg_start + 3 ..];

        // Extract SLP_TYP values: either BytePrefix(0x0A) + value, or raw
        slp_typ_a = @truncate(extract_slp_value(pkg_data));
        const remaining = if (pkg_data.len > 0 and pkg_data[0] == 0x0A)
            pkg_data[2..]
        else
            pkg_data[1..];
        slp_typ_b = @truncate(extract_slp_value(remaining));

        s5_initialized = true;

        log.debug("_S5: found: SLP_TYPa (0x{}), SLP_TYPb (0x{})", .{ slp_typ_a, slp_typ_b });
        return;
    }

    log.err("_S5: not found", .{});
    return Error.s5_not_found;
}

fn extract_slp_value(data: []const u8) u16 {
    if (data.len == 0) return 0;
    if (data[0] == 0x0A and data.len >= 2) return data[1]; // BytePrefix encoding
    return data[0]; // Raw byte
}

/// Power off the system (S5 transition).
pub fn power_off() void {
    const fadt = Acpi.get_fadt() orelse {
        log.err("power_off: no FADT", .{});
        return;
    };
    if (!s5_initialized) {
        log.err("power_off: S5 not initialized", .{});
        return;
    }

    const cmd = Pm1Control{ .sci_en = false, .bm_rld = false, .gbl_rls = false, .slp_typ = slp_typ_a, .slp_en = true };

    log.info("Powering off (SLP_TYPa={d})...", .{slp_typ_a});
    osl.write_io(@truncate(fadt.pm1a_control_block), 2, @as(u16, @bitCast(cmd)));
}

fn read_pm1_control(port: u32) Pm1Control {
    return @bitCast(osl.read_io(@as(u16, @truncate(port)), 2));
}

fn is_enabled(fadt: *align(1) const FADT) bool {
    return read_pm1_control(fadt.pm1a_control_block).sci_en;
}

fn is_pm1b_enabled(fadt: *align(1) const FADT) bool {
    return read_pm1_control(fadt.pm1b_control_block).sci_en;
}
