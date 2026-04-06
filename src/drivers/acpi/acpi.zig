const std = @import("std");

const sdt = @import("tables/sdt.zig");
const Registry = @import("tables/registry.zig").Registry;
const osl = @import("os_layer.zig");
const power = @import("power.zig");
const aml = @import("aml/aml.zig");
const executor = @import("aml/executor.zig");
const device = @import("device.zig");
const events = @import("events.zig");
const prt = @import("prt.zig");
const aml_test = @import("aml_test.zig");

const rsdp_module = @import("tables/rsdp.zig");
const rsdt_module = @import("tables/rsdt.zig");
const fadt_module = @import("tables/fadt.zig");

const Node = @import("namespace/node.zig").Node;
const Object = @import("aml/objects.zig").Object;

pub const RSDP = rsdp_module.RSDP;
pub const FADT = fadt_module.FADT;
pub const Namespace = @import("namespace/namespace.zig").Namespace;
pub const evaluate = executor.evaluate;

// Force semantic analysis of the evaluator module tree.
comptime {
    _ = &evaluate;
}

const log = std.log.scoped(.acpi);

/// Global ACPI subsystem state.
var registry: Registry = .{};
var fadt: ?*align(1) const FADT = null;
var dsdt_data: ?[]const u8 = null;
var namespace: ?Namespace = null;
var namespace_initialized: bool = false;
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
    namespace_initialized = true;

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

    // S5 sleep type extraction from namespace (§7.4.2)
    power.init_s5(&namespace.?) catch |err| {
        @panic(switch (err) {
            power.Error.s5_not_found => "ACPI: \\_S5_ not found in namespace",
            else => "ACPI: power init failed",
        });
    };

    registry.log_summary();

    log.debug("Initialization: OK", .{});

    // 8. Resolve package references (post-load fixup)
    namespace.?.resolve_references();

    // 9. Enable ACPI mode
    power.enable_acpi() catch |err| {
        @panic(switch (err) {
            power.Error.no_smi_command_port => "ACPI: No SMI command port found",
            power.Error.no_known_enable_method => "ACPI: No known enable method",
            power.Error.enable_timeout => "ACPI: Enable timeout",
            else => "ACPI: Enable failed",
        });
    };

    // 10. Run _REG methods (ACPI spec §6.5.4)
    //     Notify AML code that operation region handlers are available.
    //     Must be done before _INI so AML can access OpRegions.
    device.run_reg(&namespace.?);

    // 11. Run _INI methods (ACPI spec §6.5.1)
    //     This creates dynamically-defined names (HDAA, NICA, SLOB, etc.)
    device.run_ini(&namespace.?);

    // 12. Enumerate ACPI devices
    device.enumerate(&namespace.?);

    // 13. Parse PCI interrupt routing tables (_PRT)
    prt.init(&namespace.?);

    // 14. Initialize ACPI event subsystem (GPE + fixed events + SCI)
    events.init(&namespace.?);

    initialized = true;
    log.info("enabled", .{});
}

/// Start the ACPI event worker task.
/// Must be called after the scheduler and task caches are initialized.
pub fn start_event_worker() void {
    events.start_worker();
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

/// Resolve an ACPI namespace path (e.g., "\\_SB.PCI0").
pub fn resolve_path(
    path_str: []const u8,
) ?*const Node {
    if (namespace) |*ns| {
        return ns.resolve_path(path_str);
    }
    return null;
}

/// Evaluate an ACPI namespace object by path.
/// If it's a method, executes it. Otherwise returns its value.
pub fn evaluate_path(path_str: []const u8) ?Object {
    if (!namespace_initialized) return null;
    const node = namespace.?.resolve_path(path_str) orelse return null;
    return executor.evaluate(
        &namespace.?,
        @constCast(node),
        &.{},
    ) catch null;
}

/// Evaluate a method with arguments.
pub fn evaluate_method(
    path_str: []const u8,
    args: []const Object,
) ?Object {
    if (!namespace_initialized) return null;
    const node = namespace.?.resolve_path(path_str) orelse return null;
    return executor.evaluate(
        &namespace.?,
        @constCast(node),
        args,
    ) catch null;
}

/// Get the ACPI namespace (for debugging/enumeration).
pub fn get_namespace() ?*const Namespace {
    if (namespace) |*ns| return ns;
    return null;
}

/// Get the list of enumerated ACPI devices.
pub fn get_devices() []const device.DeviceInfo {
    return device.get_devices();
}

/// Print device list to a writer (for shell builtin).
pub fn print_devices(writer: std.io.AnyWriter) void {
    device.print_devices(writer);
}

/// Print namespace tree to a writer (for shell builtin).
/// If path is non-null, only print the subtree rooted at that node.
pub fn print_namespace_at(path: ?[]const u8, writer: std.io.AnyWriter) void {
    if (namespace) |*ns| {
        device.print_namespace_at(ns, path, writer);
    } else {
        writer.print("ACPI namespace not initialized\n", .{}) catch {};
    }
}

/// Print resources for a device path (for shell builtin).
pub fn print_crs(path_str: []const u8, writer: std.io.AnyWriter) void {
    if (!namespace_initialized) {
        writer.print("ACPI namespace not initialized\n", .{}) catch {};
        return;
    }
    device.print_device_crs(&namespace.?, path_str, writer);
}

/// Run AML tests from live namespace (QEMU -acpitable SSDTs).
pub fn run_ns_aml_tests(writer: std.io.AnyWriter) usize {
    if (!namespace_initialized) {
        writer.print("ACPI namespace not initialized\n", .{}) catch {};
        return 1;
    }
    return aml_test.run_ns_tests(&namespace.?, writer);
}

/// Get the PCI interrupt (GSI) for a device from the ACPI _PRT.
/// pin is 0-based (0=INTA, 1=INTB, 2=INTC, 3=INTD).
pub fn get_pci_interrupt(bus: u8, dev: u8, pin: u8) ?u32 {
    if (!namespace_initialized) return null;
    return prt.get_interrupt(&namespace.?, bus, dev, pin);
}

/// Print PCI interrupt routing table (for shell builtin).
pub fn print_prt(writer: std.io.AnyWriter) void {
    if (!namespace_initialized) {
        writer.print("ACPI namespace not initialized\n", .{}) catch {};
        return;
    }
    prt.printWithNs(writer, &namespace.?);
}

/// Evaluate an AML path and print the result (for shell builtin).
pub fn print_eval(path_str: []const u8, args: []const Object, writer: std.io.AnyWriter) void {
    if (!namespace_initialized) {
        writer.print("ACPI namespace not initialized\n", .{}) catch {};
        return;
    }
    const node = namespace.?.resolve_path(path_str) orelse {
        writer.print("Not found: {s}\n", .{path_str}) catch {};
        return;
    };
    const result = executor.evaluate(
        &namespace.?,
        @constCast(node),
        args,
    ) catch |err| {
        writer.print("Eval error: {s}\n", .{@errorName(err)}) catch {};
        return;
    };
    print_object(result, writer, 0);
}

/// Pretty-print an AML object with indentation for nested structures.
fn print_object(obj: Object, writer: std.io.AnyWriter, indent: usize) void {
    const spaces = "                                ";
    const prefix = spaces[0..@min(indent * 2, spaces.len)];

    switch (obj) {
        .integer => |v| writer.print("{s}Integer: 0x{x} ({d})\n", .{ prefix, v, v }) catch {},
        .string => |s| writer.print("{s}String: \"{s}\"\n", .{ prefix, s }) catch {},
        .buffer => |b| {
            writer.print("{s}Buffer ({d} bytes):", .{ prefix, b.data.len }) catch {};
            if (b.data.len <= 64) {
                // Short buffer: inline hex dump
                for (b.data) |byte| {
                    writer.print(" {X:0>2}", .{byte}) catch {};
                }
                writer.print("\n", .{}) catch {};
            } else {
                // Long buffer: multi-line hex dump
                writer.print("\n", .{}) catch {};
                var i: usize = 0;
                while (i < b.data.len) : (i += 16) {
                    writer.print("{s}  {X:0>4}:", .{ prefix, i }) catch {};
                    const end = @min(i + 16, b.data.len);
                    for (b.data[i..end]) |byte| {
                        writer.print(" {X:0>2}", .{byte}) catch {};
                    }
                    writer.print("\n", .{}) catch {};
                    if (i >= 128) {
                        writer.print("{s}  ... ({d} more bytes)\n", .{ prefix, b.data.len - i - 16 }) catch {};
                        break;
                    }
                }
            }
        },
        .package => |p| {
            writer.print("{s}Package ({d} elements):\n", .{ prefix, p.elements.len }) catch {};
            for (p.elements, 0..) |elem, i| {
                writer.print("{s}  [{d}] ", .{ prefix, i }) catch {};
                // Print element inline if simple, nested if complex
                switch (elem) {
                    .integer => |v| writer.print("Integer: 0x{x}\n", .{v}) catch {},
                    .string => |s| writer.print("String: \"{s}\"\n", .{s}) catch {},
                    .package => {
                        writer.print("Package:\n", .{}) catch {};
                        print_object(elem, writer, indent + 2);
                    },
                    .buffer => |b| writer.print("Buffer ({d} bytes)\n", .{b.data.len}) catch {},
                    .uninitialized => writer.print("(uninitialized)\n", .{}) catch {},
                    else => writer.print("{s}\n", .{@tagName(elem)}) catch {},
                }
                // Limit output for very large packages
                if (i >= 31 and p.elements.len > 32) {
                    writer.print("{s}  ... ({d} more elements)\n", .{ prefix, p.elements.len - i - 1 }) catch {};
                    break;
                }
            }
        },
        .op_region => |r| writer.print("{s}OperationRegion: {s} offset=0x{x} len=0x{x}\n", .{
            prefix, @tagName(r.space), r.offset, r.length,
        }) catch {},
        .field_unit => |f| writer.print("{s}FieldUnit: region={s} bit_offset={d} bit_width={d}\n", .{
            prefix, &f.region_name, f.bit_offset, f.bit_width,
        }) catch {},
        .method => |m| writer.print("{s}Method: {d} args, {d} bytes\n", .{
            prefix, m.arg_count, m.code.len,
        }) catch {},
        .device => writer.print("{s}Device\n", .{prefix}) catch {},
        .reference => |r| {
            writer.print("{s}Reference -> ", .{prefix}) catch {};
            print_object(r.*, writer, 0);
        },
        .uninitialized => writer.print("{s}Uninitialized\n", .{prefix}) catch {},
        else => writer.print("{s}{s}\n", .{ prefix, @tagName(obj) }) catch {},
    }
}
