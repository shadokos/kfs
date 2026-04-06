/// PCI Interrupt Routing Table (_PRT) support (ACPI spec §6.2.13).
///
/// Maps PCI interrupt pins (INTA-INTD) to system interrupt inputs.
/// The _PRT object is required under all PCI root bridges.
///
/// Two routing models:
///   1. Link Device: Source field references a PCI Interrupt Link Device
///      (PNP0C0F) whose _CRS returns the current IRQ.
///   2. Hardwired: Source field is 0, SourceIndex is the Global System
///      Interrupt (GSI) number directly.
const std = @import("std");
const node_mod = @import("namespace/node.zig");
const ns_mod = @import("namespace/namespace.zig");
const objects = @import("aml/objects.zig");
const executor = @import("aml/executor.zig");
const resources = @import("resources.zig");

const Node = node_mod.Node;
const Namespace = ns_mod.Namespace;
const Object = objects.Object;

const log = std.log.scoped(.acpi_prt);

// ---------------------------------------------------------------------------
// PRT Entry types
// ---------------------------------------------------------------------------

/// PCI interrupt pin identifiers (ACPI spec §6.2.13 Table 6.16).
pub const Pin = enum(u8) {
    inta = 0,
    intb = 1,
    intc = 2,
    intd = 3,
};

/// A single PRT routing entry.
pub const Entry = struct {
    /// Device number (slot). Extracted from Address field bits [31:16].
    /// The function number is always 0xFFFF (any function).
    device: u16,
    /// PCI interrupt pin (INTA-INTD).
    pin: Pin,
    /// If true, this is a hardwired routing (source_index is the GSI).
    /// If false, source_node points to a Link Device whose _CRS gives the IRQ.
    hardwired: bool,
    /// For hardwired: the Global System Interrupt number.
    /// For link device: the resource index in the Link Device's _CRS.
    source_index: u32,
    /// For link device routing: pointer to the Link Device node.
    /// Null for hardwired routing.
    source_node: ?*Node,
};

/// Maximum entries per PCI root bridge.
pub const MAX_PRT_ENTRIES = 64;

/// Routing table for a single PCI root bridge.
pub const RoutingTable = struct {
    entries: [MAX_PRT_ENTRIES]Entry = undefined,
    count: usize = 0,
    /// Bus number from _BBN (0 if not present).
    bus: u8 = 0,

    /// Find the routing entry for a device and pin.
    pub fn find(self: *const RoutingTable, device: u16, pin: Pin) ?*const Entry {
        for (self.entries[0..self.count]) |*entry| {
            if (entry.device == device and entry.pin == pin) {
                return entry;
            }
        }
        return null;
    }
};

// ---------------------------------------------------------------------------
// Global routing tables (static allocation)
// ---------------------------------------------------------------------------

/// Maximum PCI root bridges (PCI host bridges).
const MAX_ROOT_BRIDGES = 8;

var routing_tables: [MAX_ROOT_BRIDGES]RoutingTable = undefined;
var routing_count: usize = 0;
var initialized: bool = false;

// ---------------------------------------------------------------------------
// Initialization
// ---------------------------------------------------------------------------

/// Parse _PRT objects from all PCI root bridges in the namespace.
/// Must be called after namespace loading.
pub fn init(ns: *Namespace) void {
    routing_count = 0;
    walk_for_prt(ns, ns.root);
    initialized = true;
    log.info("Parsed {d} PCI routing tables", .{routing_count});
}

/// Walk namespace to find PCI root bridges and parse their _PRT.
fn walk_for_prt(ns: *Namespace, node: *Node) void {
    var child = node.first_child;
    while (child) |c| {
        // Check if this is a PCI root bridge
        if (c.node_type == .device and is_pci_root_bridge(ns, c)) {
            if (c.find_child("_PRT".*)) |prt_node| {
                if (routing_count < MAX_ROOT_BRIDGES) {
                    parse_prt(ns, c, prt_node, &routing_tables[routing_count]);
                    routing_count += 1;
                }
            }
        }

        // Recurse
        walk_for_prt(ns, c);
        child = c.next_sibling;
    }
}

/// Check if a device node represents a PCI root bridge.
/// PCI root bridges have _HID="PNP0A03" (PCI) or "PNP0A08" (PCIe),
/// or have a _BBN (Base Bus Number) object.
fn is_pci_root_bridge(ns: *Namespace, node: *Node) bool {
    // Check for _BBN
    if (node.find_child("_BBN".*) != null) return true;

    // Check _HID
    const hid_node = node.find_child("_HID".*) orelse return false;

    switch (hid_node.object) {
        .integer => |val| {
            // EISA ID encoding for PNP0A03 and PNP0A08
            const pnp0a03: u32 = 0x030AD041; // PCI
            const pnp0a08: u32 = 0x080AD041; // PCIe
            const id: u32 = @truncate(val);
            return id == pnp0a03 or id == pnp0a08;
        },
        .string => |s| {
            return std.mem.eql(u8, s, "PNP0A03") or std.mem.eql(u8, s, "PNP0A08");
        },
        .method => {
            // Evaluate _HID method
            const result = executor.evaluate(ns, hid_node, &.{}) catch return false;
            switch (result) {
                .integer => |val| {
                    const pnp0a03: u32 = 0x030AD041;
                    const pnp0a08: u32 = 0x080AD041;
                    const id: u32 = @truncate(val);
                    return id == pnp0a03 or id == pnp0a08;
                },
                .string => |s| {
                    return std.mem.eql(u8, s, "PNP0A03") or std.mem.eql(u8, s, "PNP0A08");
                },
                else => return false,
            }
        },
        else => return false,
    }
}

/// Parse a _PRT package into a RoutingTable.
fn parse_prt(ns: *Namespace, bridge: *Node, prt_node: *Node, table: *RoutingTable) void {
    var path_buf: [128]u8 = undefined;
    const bridge_path = bridge.full_path(&path_buf) catch "(path error)";

    // Get _BBN if present
    table.bus = 0;
    if (bridge.find_child("_BBN".*)) |bbn_node| {
        switch (bbn_node.object) {
            .integer => |val| table.bus = @truncate(val),
            else => {
                const result = executor.evaluate(ns, bbn_node, &.{}) catch null;
                if (result) |obj| {
                    if (obj.to_integer()) |val| table.bus = @truncate(val);
                }
            },
        }
    }

    // Try direct package access first (Name object)
    var prt_result: Object = undefined;
    if (prt_node.object == .package) {
        prt_result = prt_node.object;
    } else {
        // Evaluate _PRT (method or other)
        prt_result = executor.evaluate(ns, prt_node, &.{}) catch |err| {
            log.warn("{s}._PRT eval failed: {s}", .{ bridge_path, @errorName(err) });
            return;
        };
    }

    if (prt_result != .package) {
        log.warn("{s}._PRT returned {s}, expected package", .{ bridge_path, @tagName(prt_result) });
        return;
    }

    table.count = 0;

    for (prt_result.package.elements) |elem| {
        if (elem != .package) continue;
        if (table.count >= MAX_PRT_ENTRIES) break;

        const entry_pkg = elem.package;
        if (entry_pkg.elements.len < 4) continue;

        var entry: Entry = undefined;

        // Field 0: Address (DWORD) - device << 16 | 0xFFFF
        if (entry_pkg.elements[0].to_integer()) |addr| {
            entry.device = @truncate(addr >> 16);
        } else continue;

        // Field 1: Pin (Byte) - 0=INTA, 1=INTB, 2=INTC, 3=INTD
        if (entry_pkg.elements[1].to_integer()) |pin_val| {
            if (pin_val > 3) continue;
            entry.pin = @enumFromInt(@as(u8, @truncate(pin_val)));
        } else continue;

        // Field 2: Source - NamePath or 0
        // Field 3: SourceIndex
        const source = entry_pkg.elements[2];
        const source_index = entry_pkg.elements[3].to_integer() orelse 0;
        entry.source_index = @truncate(source_index);

        switch (source) {
            .integer => |val| {
                // Hardwired: Source is 0, SourceIndex is the GSI
                if (val == 0) {
                    entry.hardwired = true;
                    entry.source_node = null;
                } else {
                    continue;
                }
            },
            .reference => |ref| {
                // Link device reference (resolved by namespace fixup pass)
                entry.hardwired = false;
                entry.source_node = @fieldParentPtr("object", ref);
            },
            else => {
                log.warn("PRT[{d}] unexpected source type: {s}", .{ table.count, @tagName(source) });
                continue;
            },
        }

        table.entries[table.count] = entry;
        table.count += 1;
    }

    log.debug("{s}._PRT: {d} entries, bus {d}", .{ bridge_path, table.count, table.bus });
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Get the interrupt (GSI) for a PCI device.
/// Returns the Global System Interrupt number, or null if not found.
///
/// Parameters:
///   - bus: PCI bus number
///   - device: PCI device number (slot)
///   - pin: PCI interrupt pin (0=INTA, 1=INTB, 2=INTC, 3=INTD)
pub fn get_interrupt(ns: *Namespace, bus: u8, device: u8, pin: u8) ?u32 {
    if (!initialized) return null;
    if (pin > 3) return null;

    const int_pin: Pin = @enumFromInt(pin);

    // Find the routing table for this bus
    for (routing_tables[0..routing_count]) |*table| {
        if (table.bus != bus) continue;

        const entry = table.find(device, int_pin) orelse continue;

        if (entry.hardwired) {
            // Direct GSI mapping
            return entry.source_index;
        } else {
            // Link device: evaluate _CRS to get the interrupt
            const link_node = entry.source_node orelse return null;
            return resolve_link_interrupt(ns, link_node, entry.source_index);
        }
    }

    return null;
}

/// Resolve the interrupt from a Link Device's _CRS.
fn resolve_link_interrupt(ns: *Namespace, link_node: *Node, resource_index: u32) ?u32 {
    const crs_node = link_node.find_child("_CRS".*) orelse return null;

    const result = executor.evaluate(ns, crs_node, &.{}) catch return null;
    if (result != .buffer) return null;

    const res_list = resources.parse(result.buffer.data);

    // Find the interrupt resource at the given index
    var idx: u32 = 0;
    for (res_list.items[0..res_list.count]) |res| {
        switch (res) {
            .irq => |irq| {
                if (idx == resource_index) {
                    // Return first set bit in IRQ mask
                    var mask = irq.irq_mask;
                    var irq_num: u32 = 0;
                    while (mask != 0) : (irq_num += 1) {
                        if (mask & 1 != 0) return irq_num;
                        mask >>= 1;
                    }
                }
                idx += 1;
            },
            .extended_irq => |ext_irq| {
                if (idx == resource_index) {
                    if (ext_irq.irq_count > 0) {
                        return ext_irq.irqs[0];
                    }
                }
                idx += 1;
            },
            else => {},
        }
    }

    return null;
}

/// Get the routing tables (for debugging).
pub fn get_tables() []const RoutingTable {
    return routing_tables[0..routing_count];
}

/// Print PRT information to a writer.
pub fn print(writer: std.io.AnyWriter) void {
    printWithNs(writer, null);
}

/// Print with optional namespace for resolving Link Devices.
pub fn printWithNs(writer: std.io.AnyWriter, ns: ?*Namespace) void {
    if (!initialized or routing_count == 0) {
        writer.print("No PCI routing tables\n", .{}) catch {};
        return;
    }

    for (routing_tables[0..routing_count]) |*table| {
        writer.print("PCI Bus {d} ({d} entries):\n", .{ table.bus, table.count }) catch {};

        for (table.entries[0..table.count]) |*entry| {
            const pin_name: []const u8 = switch (entry.pin) {
                .inta => "INTA",
                .intb => "INTB",
                .intc => "INTC",
                .intd => "INTD",
            };

            if (entry.hardwired) {
                writer.print("  Dev {d:>2} {s} -> GSI {d}\n", .{
                    entry.device, pin_name, entry.source_index,
                }) catch {};
            } else {
                // Try to resolve the Link Device to get actual GSI
                var gsi: ?u32 = null;
                if (ns) |namespace| {
                    if (entry.source_node) |link_node| {
                        gsi = resolve_link_interrupt(namespace, link_node, entry.source_index);
                        if (gsi == null) {
                            // Debug: why did resolution fail?
                            var nbuf: [64]u8 = undefined;
                            const lname = link_node.full_path(&nbuf) catch "?";
                            const has_crs = link_node.find_child("_CRS".*) != null;
                            writer.print("  Dev {d:>2} {s} -> Link {s} (no _CRS: {any})\n", .{
                                entry.device, pin_name, lname, !has_crs,
                            }) catch {};
                            continue;
                        }
                    }
                }

                if (gsi) |g| {
                    writer.print("  Dev {d:>2} {s} -> GSI {d} (via Link)\n", .{
                        entry.device, pin_name, g,
                    }) catch {};
                } else {
                    writer.print("  Dev {d:>2} {s} -> Link (no source_node)\n", .{
                        entry.device, pin_name,
                    }) catch {};
                }
            }
        }
    }
}
