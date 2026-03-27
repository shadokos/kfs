/// AML FieldUnit, IndexFieldUnit, and BufferField read/write (ACPI 6.4 §5.5.2.4).
///
/// Field access involves resolving the parent OpRegion (§20.2.5.2) and
/// performing I/O in the appropriate address space (§5.5.2.4):
///   - SystemMemory (0x00): physical memory read/write
///   - SystemIO     (0x01): port I/O read/write
///   - PCI_Config   (0x02): PCI configuration space via BDF
///
/// IndexField access (§19.6.63) is a two-step operation:
/// write the byte index to the Index register, then read/write the Data register.
///
/// BufferField access (§19.6.18-§19.6.23) reads/writes bit ranges within Buffer objects.
const std = @import("std");
const objects = @import("../objects.zig");
const ns_mod = @import("../../namespace/namespace.zig");
const node_mod = @import("../../namespace/node.zig");
const path_mod = @import("../../namespace/path.zig");
const osl = @import("../../os_layer.zig");
const integer = @import("integer.zig");
const pci = @import("../../../pci/pci.zig");

const Object = objects.Object;
const Namespace = ns_mod.Namespace;
const Node = node_mod.Node;
const Error = @import("executor.zig").Error;

const log = std.log.scoped(.acpi_exec);
const to_int = integer.to_int;

// ---------------------------------------------------------------------------
// FieldUnit read (§5.5.2.4)
// ---------------------------------------------------------------------------

/// Read a FieldUnit value from its OpRegion.
/// Uses the pre-resolved region_node pointer when available (set during
/// namespace loading), falling back to §5.3 upward search via resolve_name().
pub fn read_field(
    ns: *Namespace,
    scope: *Node,
    fu: *const objects.FieldUnit,
) Error!Object {
    const region_node = resolve_region(ns, scope, fu.region_name, fu.region_node) orelse {
        log.warn("read_field: region '{s}' not found", .{
            path_mod.format_seg(&fu.region_name),
        });
        return .{ .integer = 0 };
    };

    const region = region_node.object.op_region;
    const bit_start = fu.bit_offset;
    const bit_end = bit_start + fu.bit_width;
    const byte_start = bit_start / 8;
    const byte_end = (bit_end + 7) / 8;
    const width_bytes = byte_end - byte_start;
    const addr = region.offset + byte_start;

    const raw_val: u64 = read_region(region.space, addr, width_bytes, region_node);

    // Extract the bit field from the raw value
    const bit_offset_in_byte = @as(u6, @truncate(bit_start % 8));
    const shifted = raw_val >> bit_offset_in_byte;
    const mask: u64 = if (fu.bit_width >= 64)
        0xFFFFFFFFFFFFFFFF
    else
        (@as(u64, 1) << @as(u6, @truncate(fu.bit_width))) - 1;

    return .{ .integer = shifted & mask };
}

// ---------------------------------------------------------------------------
// FieldUnit write (§5.5.2.4)
// ---------------------------------------------------------------------------

/// Write a value to a FieldUnit in its OpRegion.
pub fn write_field(
    ns: *Namespace,
    scope: *Node,
    fu: *const objects.FieldUnit,
    value: Object,
) void {
    const val = to_int(value);

    const region_node = resolve_region(ns, scope, fu.region_name, fu.region_node) orelse {
        log.warn("write_field: region '{s}' not found", .{
            path_mod.format_seg(&fu.region_name),
        });
        return;
    };

    const region = region_node.object.op_region;
    const bit_start = fu.bit_offset;
    const bit_end = bit_start + fu.bit_width;
    const byte_start = bit_start / 8;
    const byte_end = (bit_end + 7) / 8;
    const width_bytes = byte_end - byte_start;
    const bit_offset_in_byte = @as(u6, @truncate(bit_start % 8));

    // Determine write value: aligned whole-field or read-modify-write
    const write_val: u64 = if (bit_offset_in_byte == 0 and
        (fu.bit_width == 8 or fu.bit_width == 16 or
            fu.bit_width == 32 or fu.bit_width == 64))
        val
    else blk: {
        // Sub-byte or misaligned: read-modify-write (§5.5.2.4)
        const old = read_field(ns, scope, fu) catch break :blk val;
        const old_val = to_int(old);
        const mask: u64 = if (fu.bit_width >= 64)
            0xFFFFFFFFFFFFFFFF
        else
            (@as(u64, 1) << @as(u6, @truncate(fu.bit_width))) - 1;
        break :blk (old_val & ~(mask << bit_offset_in_byte)) |
            ((val & mask) << bit_offset_in_byte);
    };

    write_region(region.space, region.offset + byte_start, width_bytes, write_val, region_node);
}

// ---------------------------------------------------------------------------
// IndexFieldUnit read/write (§19.6.63)
// ---------------------------------------------------------------------------

/// Read an IndexField value: write byte index to Index register, read from Data register.
pub fn read_index_field(
    ns: *Namespace,
    scope: *Node,
    ifu: *const objects.IndexFieldUnit,
) Error!Object {
    const index_node = resolve_cached_node(ns, scope, ifu.index_name, ifu.index_node) orelse {
        log.warn("read_index_field: index '{s}' not found", .{
            path_mod.format_seg(&ifu.index_name),
        });
        return .{ .integer = 0 };
    };
    const data_node = resolve_cached_node(ns, scope, ifu.data_name, ifu.data_node) orelse {
        log.warn("read_index_field: data '{s}' not found", .{
            path_mod.format_seg(&ifu.data_name),
        });
        return .{ .integer = 0 };
    };

    // Write byte offset to Index register
    const byte_index = ifu.bit_offset / 8;
    if (index_node.object == .field_unit) {
        write_field(ns, scope, &index_node.object.field_unit, .{ .integer = byte_index });
    }

    // Read from Data register
    if (data_node.object == .field_unit) {
        return read_field(ns, scope, &data_node.object.field_unit);
    }
    return .{ .integer = 0 };
}

/// Write to an IndexField: write byte index to Index register, write value to Data register.
pub fn write_index_field(
    ns: *Namespace,
    scope: *Node,
    ifu: *const objects.IndexFieldUnit,
    value: Object,
) void {
    const index_node = resolve_cached_node(ns, scope, ifu.index_name, ifu.index_node) orelse return;
    const data_node = resolve_cached_node(ns, scope, ifu.data_name, ifu.data_node) orelse return;

    const byte_index = ifu.bit_offset / 8;
    if (index_node.object == .field_unit) {
        write_field(ns, scope, &index_node.object.field_unit, .{ .integer = byte_index });
    }
    if (data_node.object == .field_unit) {
        write_field(ns, scope, &data_node.object.field_unit, value);
    }
}

// ---------------------------------------------------------------------------
// BufferField read/write (§19.6.21)
// ---------------------------------------------------------------------------

/// Read a BufferField (created by CreateDWordField, etc.).
pub fn read_buffer_field(bf: *const objects.BufferField) Object {
    const src: *Node = @ptrCast(@alignCast(bf.source_node));
    const buf_data = switch (src.object) {
        .buffer => |b| b.data,
        else => return .{ .integer = 0 },
    };

    const bit_start = bf.bit_offset;
    const bit_end = bit_start + bf.bit_width;
    const byte_start = bit_start / 8;
    const byte_end = (bit_end + 7) / 8;

    if (byte_end > buf_data.len) return .{ .integer = 0 };

    var val: u64 = 0;
    for (byte_start..byte_end) |i| {
        val |= @as(u64, buf_data[i]) << @intCast((i - byte_start) * 8);
    }

    const bit_in_byte = @as(u6, @truncate(bit_start % 8));
    val >>= bit_in_byte;
    const mask: u64 = if (bf.bit_width >= 64)
        0xFFFFFFFFFFFFFFFF
    else
        (@as(u64, 1) << @as(u6, @truncate(bf.bit_width))) - 1;
    return .{ .integer = val & mask };
}

/// Write to a BufferField (created by CreateDWordField, etc.).
pub fn write_buffer_field(bf: *const objects.BufferField, value: Object) void {
    const src: *Node = @ptrCast(@alignCast(bf.source_node));
    const buf_data = switch (src.object) {
        .buffer => |b| b.data,
        else => return,
    };

    const val = to_int(value);
    const bit_start = bf.bit_offset;
    const bit_end = bit_start + bf.bit_width;
    const byte_start = bit_start / 8;
    const byte_end = (bit_end + 7) / 8;

    if (byte_end > buf_data.len) return;

    const mut_data = @constCast(buf_data);
    const bit_in_byte = @as(u6, @truncate(bit_start % 8));

    if (bit_in_byte == 0 and (bf.bit_width == 8 or bf.bit_width == 16 or
        bf.bit_width == 32 or bf.bit_width == 64))
    {
        // Aligned whole-field write
        for (byte_start..byte_end) |i| {
            mut_data[i] = @truncate(val >> @intCast((i - byte_start) * 8));
        }
    } else {
        // Sub-byte / misaligned: read-modify-write
        var old: u64 = 0;
        for (byte_start..byte_end) |i| {
            old |= @as(u64, mut_data[i]) << @intCast((i - byte_start) * 8);
        }
        const mask: u64 = if (bf.bit_width >= 64)
            0xFFFFFFFFFFFFFFFF
        else
            (@as(u64, 1) << @as(u6, @truncate(bf.bit_width))) - 1;
        const new = (old & ~(mask << bit_in_byte)) | ((val & mask) << bit_in_byte);
        for (byte_start..byte_end) |i| {
            mut_data[i] = @truncate(new >> @intCast((i - byte_start) * 8));
        }
    }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Resolve an OpRegion node, using a cached pointer if available.
fn resolve_region(
    ns: *Namespace,
    scope: *Node,
    region_name: [4]u8,
    cached: ?*anyopaque,
) ?*Node {
    if (cached) |ptr| {
        const node: *Node = @ptrCast(@alignCast(ptr));
        if (node.object == .op_region) return node;
    }
    const found = ns.resolve_name(scope, region_name) orelse return null;
    if (found.object != .op_region) return null;
    return found;
}

/// Resolve a cached node pointer (for IndexField index/data fields).
fn resolve_cached_node(
    ns: *Namespace,
    scope: *Node,
    name: [4]u8,
    cached: ?*anyopaque,
) ?*Node {
    if (cached) |ptr| {
        return @ptrCast(@alignCast(ptr));
    }
    return ns.resolve_name(scope, name);
}

/// Read raw bytes from an address space.
fn read_region(space: objects.AddressSpace, addr: u64, width_bytes: u32, region_node: ?*Node) u64 {
    switch (space) {
        .system_io => {
            const port: u16 = @truncate(addr);
            return switch (width_bytes) {
                1 => @as(u64, osl.read_io(port, 1)),
                2 => @as(u64, osl.read_io(port, 2)),
                else => @as(u64, osl.read_io(port, 4)),
            };
        },
        .system_memory => {
            const phys_addr: u32 = @truncate(addr);
            const ptr = osl.map_memory(phys_addr, width_bytes) catch return 0;
            defer osl.unmap_memory(ptr, width_bytes);
            var val: u64 = 0;
            for (0..width_bytes) |i| {
                val |= @as(u64, ptr[i]) << @intCast(i * 8);
            }
            return val;
        },
        .pci_config => {
            const bdf = resolve_pci_bdf(region_node) orelse return 0;
            const offset: u8 = @truncate(addr);
            return switch (width_bytes) {
                1 => @as(u64, pci.readConfig(u8, bdf.bus, bdf.dev, bdf.func, offset)),
                2 => @as(u64, pci.readConfig(u16, bdf.bus, bdf.dev, bdf.func, offset)),
                else => @as(u64, pci.readConfig(u32, bdf.bus, bdf.dev, bdf.func, offset)),
            };
        },
        else => {
            log.warn("read_region: unsupported space {s}", .{@tagName(space)});
            return 0;
        },
    }
}

/// Write raw bytes to an address space.
fn write_region(space: objects.AddressSpace, addr: u64, width_bytes: u32, value: u64, region_node: ?*Node) void {
    switch (space) {
        .system_io => {
            const port: u16 = @truncate(addr);
            switch (width_bytes) {
                1 => osl.write_io(port, 1, @truncate(value)),
                2 => osl.write_io(port, 2, @truncate(value)),
                else => osl.write_io(port, 4, @truncate(value)),
            }
        },
        .system_memory => {
            const phys_addr: u32 = @truncate(addr);
            const ptr = osl.map_memory(phys_addr, width_bytes) catch {
                log.warn("write_region: failed to map 0x{x}", .{phys_addr});
                return;
            };
            defer osl.unmap_memory(ptr, width_bytes);
            for (0..width_bytes) |i| {
                ptr[i] = @truncate(value >> @intCast(i * 8));
            }
        },
        .pci_config => {
            const bdf = resolve_pci_bdf(region_node) orelse return;
            const offset: u8 = @truncate(addr);
            switch (width_bytes) {
                1 => pci.writeConfig(u8, bdf.bus, bdf.dev, bdf.func, offset, @truncate(value)),
                2 => pci.writeConfig(u16, bdf.bus, bdf.dev, bdf.func, offset, @truncate(value)),
                else => pci.writeConfig(u32, bdf.bus, bdf.dev, bdf.func, offset, @truncate(value)),
            }
        },
        else => {
            log.warn("write_region: unsupported space {s}", .{@tagName(space)});
        },
    }
}

// ---------------------------------------------------------------------------
// PCI config space BDF resolution
// ---------------------------------------------------------------------------

const PciBdf = struct {
    bus: u8,
    dev: u5,
    func: u3,
};

/// Walk up the namespace from an OpRegion node to extract the PCI
/// bus/device/function from _ADR (device/function) and _BBN (bus number).
fn resolve_pci_bdf(region_node: ?*Node) ?PciBdf {
    const node = region_node orelse return null;

    // Walk up to find the device that owns this OpRegion
    var current: ?*const Node = node.parent;
    while (current) |n| {
        if (n.node_type == .device) {
            if (n.find_child("_ADR".*)) |adr_node| {
                const adr: u64 = switch (adr_node.object) {
                    .integer => |v| v,
                    else => 0,
                };
                return .{
                    .bus = find_pci_bus(n) orelse 0,
                    .dev = @truncate(adr >> 16),
                    .func = @truncate(adr),
                };
            }
        }
        current = n.parent;
    }
    return null;
}

/// Walk up from a PCI device to its root bridge and read _BBN (base bus number).
/// Returns null (caller defaults to 0) when no _BBN is found.
fn find_pci_bus(device_node: *const Node) ?u8 {
    var current: ?*const Node = device_node.parent;
    while (current) |n| {
        if (n.node_type == .device) {
            if (n.find_child("_BBN".*)) |bbn_node| {
                return switch (bbn_node.object) {
                    .integer => |v| @truncate(v),
                    else => null,
                };
            }
        }
        current = n.parent;
    }
    return null;
}
