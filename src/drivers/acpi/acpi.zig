const std = @import("std");

const sdt = @import("tables/sdt.zig");
const Registry = @import("tables/registry.zig").Registry;
const osl = @import("os_layer.zig");
const power = @import("power.zig");
const aml = @import("aml/aml.zig");

const rsdp_module = @import("tables/rsdp.zig");
const rsdt_module = @import("tables/rsdt.zig");
const fadt_module = @import("tables/fadt.zig");

pub const RSDP = rsdp_module.RSDP;
pub const FADT = fadt_module.FADT;
pub const Namespace = @import("namespace/namespace.zig").Namespace;

const log = std.log.scoped(.acpi);

/// Global ACPI subsystem state.
var registry: Registry = .{};
var fadt: ?*align(1) const FADT = null;
var dsdt_data: ?[]const u8 = null;
var namespace: ?Namespace = null;
var initialized: bool = false;

// Public API ----------------------------------------------------------------
//
/// Initialize the ACPI subsystem. Called from boot.zig.
pub fn init() void {
    // 1. Find RSDP from multiboot2 tags
    const rsdp = rsdp_module.find_from_multiboot() catch |err| {
        @panic(switch (err) {
            rsdp_module.Error.not_found => "ACPI: RSDP not found",
            rsdp_module.Error.invalid_checksum => "ACPI: RSDP invalid checksum",
        });
    };

    // 2. Parse RSDT and discover all tables
    registry.register_address(rsdp.rsdt_address) catch |err| {
        log.err("ACPI: Failed to register RSDT: {s}", .{@errorName(err)});
    };

    rsdt_module.parse(rsdp.rsdt_address, &registry) catch |err| {
        @panic(switch (err) {
            error.invalid_checksum => "ACPI: RSDT invalid checksum",
            error.map_failed => "ACPI: Failed to map RSDT",
        });
    };

    // 3. Map FADT
    fadt = registry.map_typed("FACP".*, FADT) catch |err| {
        log.err("ACPI: FADT (FACP) not found or invalid: {s}", .{@errorName(err)});
        @panic("ACPI: FADT not found or invalid");
    };
    // power.set_fadt(fadt.?);

    // 4. Map DSDT and extract S5 sleep values
    registry.register_address(fadt.?.dsdt) catch |err| {
        log.warn("ACPI: Failed to register DSDT: {s}", .{@errorName(err)});
    };
    dsdt_data = registry.map_aml("DSDT".*) catch |err| {
        log.err("ACPI: DSDT not found or invalid: {s}", .{@errorName(err)});
        @panic("ACPI: DSDT not found or invalid");
    };

    // 5. Load AML namespace
    namespace = Namespace{};
    namespace.?.init_in_place() catch @panic("ACPI: namespace init failed");

    // 6. Load DSDT AML into namespace
    aml.load_table(&namespace.?, dsdt_data.?) catch |err| {
        log.err("ACPI: Failed to load DSDT AML: {s}", .{@errorName(err)});
    };

    // 7. Load all SSDTs
    for (registry.iter()) |entry| {
        if (std.mem.eql(u8, &entry.signature, "SSDT")) {
            const ssdt_data = Registry.map_aml_entry(&entry, "SSDT") catch |err| {
                log.warn("ACPI: Failed to map SSDT at 0x{x}: {s}", .{ entry.physical_address, @errorName(err) });
                continue;
            };
            aml.load_table(&namespace.?, ssdt_data) catch |err| {
                log.warn("ACPI: Failed to load SSDT: {s}", .{@errorName(err)});
            };
        }
    }

    // S5 sleep type extraction (temporary workaround until full AML evaluation)
    power.init_s5_from_dsdt(dsdt_data.?) catch |err| {
        @panic(switch (err) {
            power.Error.s5_not_found => "ACPI: _S5 not found in DSDT",
            else => "ACPI: power init failed",
        });
    };

    registry.log_summary();

    log.debug("Initialization: OK", .{});

    // 5. Enable ACPI mode
    power.enable_acpi() catch |err| {
        @panic(switch (err) {
            power.Error.no_smi_command_port => "ACPI: No SMI command port found",
            power.Error.no_known_enable_method => "ACPI: No known enable method",
            power.Error.enable_timeout => "ACPI: Enable timeout",
            else => "ACPI: Enable failed",
        });
    };

    initialized = true;
    log.info("enabled", .{});
}

/// Shut down the system (S5).
pub fn power_off() void {
    power.power_off();
}

/// Get the table registry (for debugging or advanced use).
pub fn get_registry() *const Registry {
    return &registry;
}

pub fn get_fadt() ?*align(1) const FADT {
    return fadt;
}

pub fn print_namespace() void {
    if (namespace) |ns| {
        ns.dump();
    } else {
        log.warn("ACPI namespace not initialized", .{});
    }
}
