const std = @import("std");
const Acpi = @import("acpi.zig");
const osl = @import("os_layer.zig");
const FADT = @import("tables/fadt.zig").FADT;
const sdt = @import("tables/sdt.zig");
const Namespace = @import("namespace/namespace.zig").Namespace;

const log = std.log.scoped(.@"acpi(power)");

/// PM1 Control Register (PM1a_CNT / PM1b_CNT).
/// Register layout: ACPI 6.4 §4.8.1.2 (PM1 Control Registers).
/// SLP_TYP and SLP_EN fields: §4.8.3.2 (Sleeping/Wake Control).
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

/// Initialize S5 sleep type values from the \_S5_ namespace object.
///
/// The \_S5_ object is a Package containing sleep type values (§7.4.2):
///   Name(\_S5_, Package() { SLP_TYPa, SLP_TYPb, Reserved, Reserved })
///
/// Elements [0] and [1] are the SLP_TYP values for PM1a_CNT and PM1b_CNT
/// respectively (§4.8.3.2 SLP_TYP field).
pub fn init_s5(ns: *Namespace) Error!void {
    const node = ns.resolve_path("\\_S5_") orelse {
        log.err("\\_S5_: not found in namespace", .{});
        return Error.s5_not_found;
    };

    switch (node.object) {
        .package => |pkg| {
            if (pkg.elements.len < 2) {
                log.err("\\_S5_: package has fewer than 2 elements", .{});
                return Error.s5_not_found;
            }
            slp_typ_a = @truncate(extract_int(pkg.elements[0]));
            slp_typ_b = @truncate(extract_int(pkg.elements[1]));
        },
        else => {
            log.err("\\_S5_: expected package, got {s}", .{node.object.type_name()});
            return Error.s5_not_found;
        },
    }

    s5_initialized = true;
    log.debug("\\_S5_: SLP_TYPa={d}, SLP_TYPb={d}", .{ slp_typ_a, slp_typ_b });
}

fn extract_int(obj: @import("aml/objects.zig").Object) u64 {
    return switch (obj) {
        .integer => |v| v,
        else => 0,
    };
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
