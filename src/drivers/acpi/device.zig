/// ACPI device enumeration: walks the namespace to discover devices
/// and evaluate their standard methods (_STA, _HID, _ADR, _UID, _CRS).
const std = @import("std");
const node_mod = @import("namespace/node.zig");
const path_mod = @import("namespace/path.zig");
const ns_mod = @import("namespace/namespace.zig");
const objects = @import("aml/objects.zig");
const executor = @import("aml/executor.zig");
const resources = @import("resources.zig");

const Node = node_mod.Node;
const Namespace = ns_mod.Namespace;
const Object = objects.Object;

const log = std.log.scoped(.acpi_dev);

// ---------------------------------------------------------------------------
// Device status flags (ACPI spec §6.3.7, _STA return value)
// ---------------------------------------------------------------------------

pub const DeviceStatus = packed struct(u32) {
    present: bool, // bit 0
    enabled: bool, // bit 1
    visible_in_ui: bool, // bit 2
    functioning: bool, // bit 3
    battery_present: bool, // bit 4
    _reserved: u27 = 0,
};

/// Default status when _STA is not defined (ACPI spec: device is present,
/// enabled, shown in UI, and functioning).
const DEFAULT_STATUS: DeviceStatus = .{
    .present = true,
    .enabled = true,
    .visible_in_ui = true,
    .functioning = true,
    .battery_present = false,
};

// ---------------------------------------------------------------------------
// Device info
// ---------------------------------------------------------------------------

pub const DeviceInfo = struct {
    node: *const Node,
    path_buf: [128]u8 = undefined,
    path_len: usize = 0,
    status: DeviceStatus = DEFAULT_STATUS,
    hid: ?u64 = null, // _HID as EISA ID or integer
    hid_str: ?[]const u8 = null, // _HID as string
    adr: ?u64 = null, // _ADR
    uid: ?u64 = null, // _UID as integer
    uid_str: ?[]const u8 = null, // _UID as string
    crs: ?resources.ResourceList = null, // _CRS parsed resources

    pub fn path(self: *const DeviceInfo) []const u8 {
        return self.path_buf[0..self.path_len];
    }
};

// ---------------------------------------------------------------------------
// Enumeration results (static buffer, no allocator needed)
// ---------------------------------------------------------------------------

const MAX_DEVICES = 128;

var device_list: [MAX_DEVICES]DeviceInfo = undefined;
var device_count: usize = 0;
var enumerated: bool = false;

/// Enumerate all devices under \_SB (and other scopes).
/// Evaluates _STA, _HID, _ADR, _UID for each device node.
pub fn enumerate(ns: *Namespace) void {
    device_count = 0;
    walk_devices(ns, ns.root);
    enumerated = true;
    log.debug("Enumerated {d} devices", .{device_count});
}

/// Get the list of discovered devices.
pub fn get_devices() []const DeviceInfo {
    return device_list[0..device_count];
}

/// Print device list to a writer.
pub fn print_devices(writer: std.io.AnyWriter) void {
    if (!enumerated) {
        writer.print("ACPI devices not enumerated\n", .{}) catch {};
        return;
    }

    writer.print(
        "{s:<40} {s:<6} {s:<16} {s:<8}\n",
        .{ "PATH", "STATUS", "HID", "ADR" },
    ) catch {};
    writer.print(
        "{s:-<40} {s:-<6} {s:-<16} {s:-<8}\n",
        .{ "", "", "", "" },
    ) catch {};

    for (device_list[0..device_count]) |*dev| {
        const status_str: []const u8 = if (dev.status.present and dev.status.functioning)
            "OK"
        else if (dev.status.present)
            "PRES"
        else
            "OFF";

        var hid_buf: [16]u8 = undefined;
        const hid_str = if (dev.hid_str) |s|
            s
        else if (dev.hid) |h|
            format_eisa_id(h, &hid_buf)
        else
            "-";

        var adr_buf: [10]u8 = undefined;
        const adr_str = if (dev.adr) |a|
            std.fmt.bufPrint(&adr_buf, "0x{x:0>4}", .{a}) catch "-"
        else
            "-";

        writer.print(
            "{s:<40} {s:<6} {s:<16} {s:<8}\n",
            .{ dev.path(), status_str, hid_str, adr_str },
        ) catch {};
    }
}

/// Print resources for a device (by path) to a writer.
pub fn print_device_crs(
    ns: *Namespace,
    path_str: []const u8,
    writer: std.io.AnyWriter,
) void {
    const node = ns.resolve_path(path_str) orelse {
        writer.print("Not found: {s}\n", .{path_str}) catch {};
        return;
    };
    const crs_node = node.find_child("_CRS".*) orelse {
        writer.print("{s}: no _CRS method\n", .{path_str}) catch {};
        return;
    };
    const result = executor.evaluate(ns, crs_node, &.{}) catch |err| {
        writer.print("{s}._CRS eval error: {s}\n", .{ path_str, @errorName(err) }) catch {};
        return;
    };
    if (result != .buffer) {
        writer.print("{s}._CRS returned {s} (expected buffer)\n", .{
            path_str, @tagName(result),
        }) catch {};
        return;
    }
    writer.print("{s}._CRS ({d} bytes):\n", .{ path_str, result.buffer.data.len }) catch {};
    const res_list = resources.parse(result.buffer.data);
    resources.print(&res_list, writer);
}

/// Print namespace tree to a writer.
/// If path is non-null, only print the subtree rooted at that node.
pub fn print_namespace_at(ns: *Namespace, path: ?[]const u8, writer: std.io.AnyWriter) void {
    if (path) |p| {
        const node = ns.resolve_path(p) orelse {
            writer.print("Not found: {s}\n", .{p}) catch {};
            return;
        };
        writer.print("{s}:\n", .{p}) catch {};
        print_node(node, writer, 0);
    } else {
        writer.print("ACPI Namespace:\n", .{}) catch {};
        print_node(ns.root, writer, 0);
    }
}

// ---------------------------------------------------------------------------
// Internal
// ---------------------------------------------------------------------------

fn walk_devices(ns: *Namespace, node: *Node) void {
    var child = node.first_child;
    while (child) |c| {
        if (c.node_type == .device) {
            if (device_count < MAX_DEVICES) {
                var info = DeviceInfo{ .node = c };
                const p = c.full_path(&info.path_buf) catch "(path error)";
                info.path_len = p.len;

                // Evaluate _STA
                if (c.find_child("_STA".*)) |sta_node| {
                    const result = executor.evaluate(
                        ns,
                        sta_node,
                        &.{},
                    ) catch null;
                    if (result) |obj| {
                        if (obj.to_integer()) |val| {
                            info.status = @bitCast(@as(u32, @truncate(val)));
                        }
                    }
                }
                // else: default status (present + functioning)

                // Evaluate _HID
                if (c.find_child("_HID".*)) |hid_node| {
                    switch (hid_node.object) {
                        .integer => |val| info.hid = val,
                        .string => |s| info.hid_str = s,
                        else => {
                            const result = executor.evaluate(
                                ns,
                                hid_node,
                                &.{},
                            ) catch null;
                            if (result) |obj| switch (obj) {
                                .integer => |v| info.hid = v,
                                .string => |s| info.hid_str = s,
                                else => {},
                            };
                        },
                    }
                }

                // Evaluate _ADR
                if (c.find_child("_ADR".*)) |adr_node| {
                    switch (adr_node.object) {
                        .integer => |val| info.adr = val,
                        else => {
                            const result = executor.evaluate(
                                ns,
                                adr_node,
                                &.{},
                            ) catch null;
                            if (result) |obj| {
                                if (obj.to_integer()) |v| info.adr = v;
                            }
                        },
                    }
                }

                // Evaluate _UID
                if (c.find_child("_UID".*)) |uid_node| {
                    switch (uid_node.object) {
                        .integer => |val| info.uid = val,
                        .string => |s| info.uid_str = s,
                        else => {},
                    }
                }

                // Evaluate _CRS
                if (c.find_child("_CRS".*)) |crs_node| {
                    const result = executor.evaluate(
                        ns,
                        crs_node,
                        &.{},
                    ) catch null;
                    if (result) |obj| {
                        if (obj == .buffer) {
                            info.crs = resources.parse(obj.buffer.data);
                        }
                    }
                }

                device_list[device_count] = info;
                device_count += 1;
            }
        }

        // Recurse into children (devices can be nested)
        walk_devices(ns, c);
        child = c.next_sibling;
    }
}

fn print_node(
    node: *const Node,
    writer: std.io.AnyWriter,
    depth: usize,
) void {
    if (depth > 20) return;

    const colors = @import("colors");
    const name = path_mod.format_seg(&node.name);
    const type_str = @tagName(node.node_type);
    const obj_str = @tagName(node.object);
    const support = node_support_level(node);

    // Indentation
    var i: usize = 0;
    while (i < depth * 2) : (i += 1) {
        writer.writeByte(' ') catch {};
    }

    writer.print("{s} [{s}] {s}", .{ name, type_str, obj_str }) catch {};

    // Show value for interesting types
    switch (node.object) {
        .integer => |v| writer.print(" = 0x{x}", .{v}) catch {},
        .string => |s| writer.print(" = \"{s}\"", .{s}) catch {},
        .op_region => |r| writer.print(" ({s} 0x{x}+0x{x})", .{
            @tagName(r.space), r.offset, r.length,
        }) catch {},
        else => {},
    }

    // Show support hint for non-full items
    if (support == .partial) {
        writer.print(" {s}[partial]{s}", .{ colors.yellow, colors.reset }) catch {};
    } else if (support == .unsupported) {
        writer.print(" {s}[unsupported]{s}", .{ colors.red, colors.reset }) catch {};
    }

    writer.print("{s}\n", .{colors.reset}) catch {};

    var child = node.first_child;
    while (child) |c| {
        print_node(c, writer, depth + 1);
        child = c.next_sibling;
    }
}

const SupportLevel = enum {
    full,
    partial,
    unsupported,

    /// Return the worse of two support levels.
    fn merge(a: SupportLevel, b: SupportLevel) SupportLevel {
        if (a == .unsupported or b == .unsupported) return .unsupported;
        if (a == .partial or b == .partial) return .partial;
        return .full;
    }
};

/// Determine the interpreter support level for a namespace node.
/// For methods and containers, this considers sibling/child nodes to detect
/// whether the scope contains unsupported OpRegions or fields.
fn node_support_level(node: *const Node) SupportLevel {
    const intrinsic = intrinsic_support(node);

    switch (node.object) {
        // Methods: inherit the worst support level from their enclosing scope.
        // A method inside a device with EC OpRegions will likely access those fields.
        .method => {
            const scope_level = scope_support(node.parent orelse return intrinsic);
            return SupportLevel.merge(intrinsic, scope_level);
        },

        // Containers: propagate worst child level so devices with unsupported
        // regions are immediately visible.
        .device, .thermal_zone, .power_resource => {
            return SupportLevel.merge(intrinsic, children_support(node));
        },

        else => return intrinsic,
    }
}

/// Support level based only on the node's own type (no scope analysis).
fn intrinsic_support(node: *const Node) SupportLevel {
    const AddressSpace = objects.AddressSpace;

    return switch (node.object) {
        .integer,
        .string,
        .buffer,
        .package,
        .debug_object,
        .buffer_field,
        .reference,
        .index_field_unit,
        .uninitialized,
        => .full,

        .method => .full,
        .device => .full,
        .thermal_zone => .full,
        .power_resource => .full,

        .mutex => .partial,
        .event => .partial,
        .processor => .partial,

        .op_region => |r| switch (r.space) {
            AddressSpace.system_memory,
            AddressSpace.system_io,
            AddressSpace.pci_config,
            AddressSpace.system_cmos,
            AddressSpace.pci_bar_target,
            => .full,
            else => .unsupported,
        },

        .field_unit => |fu| region_field_support(fu.region_node),
        .bank_field_unit => |bfu| region_field_support(bfu.region_node),
    };
}

/// Check if a field's backing OpRegion is in a supported address space.
fn region_field_support(region_ptr: ?*anyopaque) SupportLevel {
    const AddressSpace = objects.AddressSpace;
    const rn = region_ptr orelse return .full;
    const region_node: *const Node = @ptrCast(@alignCast(rn));
    if (region_node.object == .op_region) {
        return switch (region_node.object.op_region.space) {
            AddressSpace.system_memory,
            AddressSpace.system_io,
            AddressSpace.pci_config,
            AddressSpace.system_cmos,
            AddressSpace.pci_bar_target,
            => .full,
            else => .unsupported,
        };
    }
    return .full;
}

/// Scan direct children of a scope for their worst intrinsic support level.
/// Used to determine whether methods in this scope are likely affected.
/// Only considers OpRegions and fields (the main source of unsupported features).
fn scope_support(scope: *const Node) SupportLevel {
    var worst: SupportLevel = .full;
    var child = scope.first_child;
    while (child) |c| {
        switch (c.object) {
            .op_region, .field_unit, .bank_field_unit, .mutex, .event => {
                worst = SupportLevel.merge(worst, intrinsic_support(c));
                if (worst == .unsupported) return .unsupported;
            },
            else => {},
        }
        child = c.next_sibling;
    }
    return worst;
}

/// Scan direct children for their worst intrinsic support level.
/// Used for container nodes (device, thermal_zone, etc.).
fn children_support(node: *const Node) SupportLevel {
    var worst: SupportLevel = .full;
    var child = node.first_child;
    while (child) |c| {
        const level = intrinsic_support(c);
        worst = SupportLevel.merge(worst, level);
        if (worst == .unsupported) return .unsupported;
        child = c.next_sibling;
    }
    return worst;
}

/// Format an EISA ID (packed u32) into a human-readable string like "PNP0A03".
fn format_eisa_id(id: u64, buf: *[16]u8) []const u8 {
    const val: u32 = @truncate(id);

    // EISA ID encoding: 3 compressed ASCII chars + 4 hex digits
    // Bits 15-10: char1, 9-5: char2, 4-0: char3 (biased by 0x40)
    const c1: u8 = @truncate(((val >> 2) & 0x1F) + 0x40);
    const c2: u8 = @truncate((((val & 0x03) << 3) | ((val >> 13) & 0x07)) + 0x40);
    const c3: u8 = @truncate(((val >> 8) & 0x1F) + 0x40);
    const product: u16 = @truncate(
        ((val >> 16) & 0xFF) | (((val >> 24) & 0xFF) << 8),
    );

    // Swap bytes for display
    const hi: u8 = @truncate(product >> 8);
    const lo: u8 = @truncate(product);

    return std.fmt.bufPrint(buf, "{c}{c}{c}{X:0>2}{X:0>2}", .{
        c1, c2, c3, hi, lo,
    }) catch "?";
}

/// Execute _INI methods according to ACPI spec §6.5.1.
/// Must be called before enumerate() to populate dynamically-created names.
///
/// Order:
///   1. Execute \_SB._INI (if it exists)
///   2. Execute \._INI (root scope, if it exists)
///   3. Walk the tree: for each device/scope with _STA present (or no _STA),
///      execute its _INI if it has one.
pub fn run_ini(ns: *Namespace) void {
    log.info("Running _INI methods...", .{});
    var count: usize = 0;

    // 1. Execute \_SB._INI first (ACPI spec §6.5.1)
    if (ns.root.find_child("_SB_".*)) |sb| {
        if (sb.find_child("_INI".*)) |ini| {
            log.debug("Executing \\_SB._INI", .{});
            _ = executor.evaluate(ns, ini, &.{}) catch |err| {
                log.warn("\\_SB._INI failed: {s}", .{@errorName(err)});
            };
            count += 1;
        }
    }

    // 2. Execute \._INI (root scope _INI)
    if (ns.root.find_child("_INI".*)) |ini| {
        log.debug("Executing \\._INI", .{});
        _ = executor.evaluate(ns, ini, &.{}) catch |err| {
            log.warn("\\._INI failed: {s}", .{@errorName(err)});
        };
        count += 1;
    }

    // 3. Recursively walk devices and execute their _INI
    //    Only for devices whose _STA indicates present (or has no _STA).
    walk_ini(ns, ns.root, &count);

    log.info("Executed {d} _INI methods", .{count});
}

fn walk_ini(ns: *Namespace, node: *Node, count: *usize) void {
    var child = node.first_child;
    while (child) |c| {
        defer child = c.next_sibling;

        // Only process devices and scopes (not methods, fields, etc.)
        switch (c.node_type) {
            .device, .scope, .processor, .thermal_zone => {},
            else => continue,
        }

        // For devices: check _STA first. If _STA exists and says
        // not present, skip this device's _INI (ACPI spec §6.5.1).
        if (c.node_type == .device) {
            if (c.find_child("_STA".*)) |sta_node| {
                const result = executor.evaluate(
                    ns,
                    sta_node,
                    &.{},
                ) catch null;
                if (result) |obj| {
                    if (obj.to_integer()) |val| {
                        const status: DeviceStatus = @bitCast(@as(u32, @truncate(val)));
                        if (!status.present) continue;
                    }
                }
            }
            // No _STA → device is assumed present (ACPI spec §6.3.7)
        }

        // Execute _INI if present (skip \_SB._INI, already done above)
        if (c.find_child("_INI".*)) |ini| {
            // Avoid re-executing \_SB._INI
            const is_sb = blk: {
                if (c.parent) |p| {
                    if (p.node_type == .root and std.mem.eql(u8, &c.name, "_SB_")) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            if (!is_sb) {
                var path_buf: [128]u8 = undefined;
                const dev_path = c.full_path(&path_buf) catch "(path error)";
                log.debug("Executing {s}._INI", .{dev_path});
                _ = executor.evaluate(ns, ini, &.{}) catch |err| {
                    log.warn("{s}._INI failed: {s}", .{ dev_path, @errorName(err) });
                };
                count.* += 1;
            }
        }

        // Recurse into children
        walk_ini(ns, c, count);
    }
}

// ---------------------------------------------------------------------------
// _REG (Region Handler) support (ACPI spec §6.5.4)
// ---------------------------------------------------------------------------

/// Execute _REG methods to notify AML code that operation region handlers
/// are available (ACPI spec §6.5.4).
///
/// For each scope containing OpRegions, if a _REG method exists, it is called
/// with (_REG(RegionSpace, 1)) for each unique address space type found in
/// that scope.
///
/// Per ACPI spec, these spaces are always available (handler is implicit):
///   - SystemIO (0x01)
///   - SystemMemory (0x00)
///   - PCI_Config (0x02) on root bus with _BBN
///
/// Must be called after namespace loading and before device enumeration.
pub fn run_reg(ns: *Namespace) void {
    log.info("Running _REG methods...", .{});
    var count: usize = 0;
    walk_reg(ns, ns.root, &count);
    log.info("Executed {d} _REG notifications", .{count});
}

/// Walk namespace and invoke _REG methods for scopes containing OpRegions.
fn walk_reg(ns: *Namespace, node: *Node, count: *usize) void {
    const AddressSpace = objects.AddressSpace;

    // Collect unique address spaces in this scope's direct children
    var space_set: [16]u8 = undefined;
    var space_count: usize = 0;

    var child = node.first_child;
    while (child) |c| {
        if (c.object == .op_region) {
            const space_id: u8 = @intFromEnum(c.object.op_region.space);
            // Check if already in set
            var found = false;
            for (space_set[0..space_count]) |s| {
                if (s == space_id) {
                    found = true;
                    break;
                }
            }
            if (!found and space_count < space_set.len) {
                space_set[space_count] = space_id;
                space_count += 1;
            }
        }
        child = c.next_sibling;
    }

    // If this scope has OpRegions and a _REG method, invoke it for each space
    if (space_count > 0) {
        if (node.find_child("_REG".*)) |reg_node| {
            var path_buf: [128]u8 = undefined;
            const scope_path = node.full_path(&path_buf) catch "(path error)";

            // Call _REG(space, 1) for each address space found
            for (space_set[0..space_count]) |space_id| {
                // Skip always-available spaces (SystemMemory, SystemIO, PCI_Config)
                const space: AddressSpace = @enumFromInt(space_id);
                switch (space) {
                    AddressSpace.system_memory,
                    AddressSpace.system_io,
                    AddressSpace.pci_config,
                    => continue,
                    else => {},
                }

                log.debug("{s}._REG({s}, 1)", .{ scope_path, @tagName(space) });

                const args = [_]Object{
                    .{ .integer = space_id },
                    .{ .integer = 1 }, // Connect handler
                };
                _ = executor.evaluate(ns, reg_node, &args) catch |err| {
                    log.warn("{s}._REG failed: {s}", .{ scope_path, @errorName(err) });
                };
                count.* += 1;
            }
        }
    }

    // Recurse into children (devices, scopes, thermal zones, etc.)
    child = node.first_child;
    while (child) |c| {
        switch (c.node_type) {
            .device, .scope, .processor, .thermal_zone, .root => {
                walk_reg(ns, c, count);
            },
            else => {},
        }
        child = c.next_sibling;
    }
}
