/// ACPI event subsystem: SCI interrupt handler, GPE dispatch, fixed events.
///
/// Architecture (ACPI 6.4 §5.6.4):
///   - Top-half (IRQ context): read status registers, clear bits, queue events
///   - Bottom-half (task context): evaluate AML methods for GPE handlers,
///     dispatch fixed event handlers (power button, etc.)
///
/// GPE register layout (§4.8.4):
///   GPE0_STS at gpe0_block, GPE0_EN at gpe0_block + gpe0_length/2
///   Each bit corresponds to a GPE number; the handler method is
///   \_GPE._Exx (edge) or \_GPE._Lxx (level) where xx is hex.
///
/// PM1 fixed event register layout (§4.8.1):
///   PM1_STS at pm1a_event_block, PM1_EN at pm1a_event_block + pm1_event_length/2
///   Bit 8 = power button, bit 9 = sleep button (§4.8.1.1 Table 4.11).
const std = @import("std");
const osl = @import("os_layer.zig");
const pic = @import("../pic/pic.zig");
const cpu = @import("../../cpu.zig");
const executor = @import("aml/executor.zig");
const ns_mod = @import("namespace/namespace.zig");
const node_mod = @import("namespace/node.zig");

const Namespace = ns_mod.Namespace;
const Node = node_mod.Node;
const Object = @import("aml/objects.zig").Object;

const log = std.log.scoped(.@"acpi(events)");

// -- PM1 Status Register (§4.8.1.1 Table 4.11) ------------------------------

const Pm1Status = packed struct(u16) {
    tmr_sts: bool, // bit 0
    _reserved1: u3, // bits 1-3
    bm_sts: bool, // bit 4
    gbl_sts: bool, // bit 5
    _reserved2: u2, // bits 6-7
    pwrbtn_sts: bool, // bit 8
    slpbtn_sts: bool, // bit 9
    rtc_sts: bool, // bit 10
    _reserved3: u4, // bits 11-14
    wak_sts: bool, // bit 15
};

const Pm1Enable = packed struct(u16) {
    tmr_en: bool, // bit 0
    _reserved1: u4, // bits 1-4
    gbl_en: bool, // bit 5
    _reserved2: u2, // bits 6-7
    pwrbtn_en: bool, // bit 8
    slpbtn_en: bool, // bit 9
    rtc_en: bool, // bit 10
    _reserved3: u5, // bits 11-15
};

// -- Event queue (lockless ring buffer, single-producer single-consumer) -----

const EventType = enum(u8) {
    gpe,
    power_button,
    sleep_button,
};

const PendingEvent = struct {
    event_type: EventType,
    gpe_number: u8,
};

const EVENT_QUEUE_SIZE = 32;

var event_queue: [EVENT_QUEUE_SIZE]PendingEvent = undefined;
var queue_head: usize = 0; // consumer reads here
var queue_tail: usize = 0; // producer writes here

fn enqueue_event(ev: PendingEvent) void {
    const next = (queue_tail + 1) % EVENT_QUEUE_SIZE;
    if (next == queue_head) {
        // Queue full, drop event (should not happen in practice)
        return;
    }
    event_queue[queue_tail] = ev;
    queue_tail = next;
}

fn dequeue_event() ?PendingEvent {
    if (queue_head == queue_tail) return null;
    const ev = event_queue[queue_head];
    queue_head = (queue_head + 1) % EVENT_QUEUE_SIZE;
    return ev;
}

// -- Cached FADT I/O port addresses ------------------------------------------

var pm1a_sts_port: u16 = 0;
var pm1a_en_port: u16 = 0;
var gpe0_sts_port: u16 = 0;
var gpe0_en_port: u16 = 0;
var initialized: bool = false;
var ns: *Namespace = undefined;

// -- Register access helpers -------------------------------------------------

fn read_pm1_status() Pm1Status {
    return @bitCast(osl.read_io(pm1a_sts_port, 2));
}

fn write_pm1_status(val: Pm1Status) void {
    osl.write_io(pm1a_sts_port, 2, @as(u16, @bitCast(val)));
}

fn read_pm1_enable() Pm1Enable {
    return @bitCast(osl.read_io(pm1a_en_port, 2));
}

fn write_pm1_enable(val: Pm1Enable) void {
    osl.write_io(pm1a_en_port, 2, @as(u16, @bitCast(val)));
}

fn read_gpe0_status() u16 {
    return osl.read_io(gpe0_sts_port, 2);
}

fn write_gpe0_status(val: u16) void {
    osl.write_io(gpe0_sts_port, 2, val);
}

fn read_gpe0_enable() u16 {
    return osl.read_io(gpe0_en_port, 2);
}

fn write_gpe0_enable(val: u16) void {
    osl.write_io(gpe0_en_port, 2, val);
}

// -- SCI interrupt handler (top-half, IRQ context) ---------------------------

fn sci_handler(_: @import("../../interrupts.zig").InterruptFrame) void {
    if (!initialized) {
        pic.ack(.ACPI);
        return;
    }

    // 1. Check PM1 fixed events (§4.8.1.1)
    const pm1_sts = read_pm1_status();
    const pm1_en = read_pm1_enable();
    log.debug("SCI: PM1_STS=0x{X:0>4} PM1_EN=0x{X:0>4}", .{
        @as(u16, @bitCast(pm1_sts)),
        @as(u16, @bitCast(pm1_en)),
    });

    if (pm1_sts.pwrbtn_sts and pm1_en.pwrbtn_en) {
        // Clear power button status (write-1-to-clear)
        write_pm1_status(@bitCast(@as(u16, 1 << 8)));
        enqueue_event(.{ .event_type = .power_button, .gpe_number = 0 });
    }

    if (pm1_sts.slpbtn_sts and pm1_en.slpbtn_en) {
        write_pm1_status(@bitCast(@as(u16, 1 << 9)));
        enqueue_event(.{ .event_type = .sleep_button, .gpe_number = 0 });
    }

    // 2. Check GPE events (§4.8.4)
    const gpe_sts = read_gpe0_status();
    const gpe_en = read_gpe0_enable();
    const active_gpes = gpe_sts & gpe_en;

    if (active_gpes != 0) {
        // Clear active GPE status bits (write-1-to-clear)
        write_gpe0_status(active_gpes);

        // Enqueue each active GPE (pop lowest set bit each iteration)
        var remaining = active_gpes;
        while (remaining != 0) {
            const bit: u8 = @ctz(remaining);
            enqueue_event(.{ .event_type = .gpe, .gpe_number = bit });
            remaining &= remaining - 1;
        }
    }

    // Wake up the worker task
    worker_wake();

    pic.ack(.ACPI);
}

// -- Worker task synchronization ---------------------------------------------
//
// The worker blocks on a wait queue when the event queue is empty, removing
// itself from the run queue. The ISR wakes it up when new events arrive.

const WaitQueue = @import("../../task/wait_queue.zig").WaitQueue;

var worker_wq: WaitQueue(.{
    .predicate = struct {
        fn pred(_: *void, _: ?*void) bool {
            // Wake up if there are pending events in the queue
            return @atomicLoad(usize, &queue_tail, .acquire) !=
                @atomicLoad(usize, &queue_head, .acquire);
        }
    }.pred,
}) = .{};

fn worker_wake() void {
    worker_wq.try_unblock();
}

// -- Worker task (bottom-half, task context) ----------------------------------

fn acpi_worker(_: usize) u8 {
    const scheduler = @import("../../task/scheduler.zig");
    log.info("ACPI event worker started", .{});

    while (true) {
        // Process all pending events
        while (dequeue_event()) |event| {
            log.debug("dispatch: {s} (gpe={d})", .{ @tagName(event.event_type), event.gpe_number });
            switch (event.event_type) {
                .gpe => handle_gpe(event.gpe_number),
                .power_button => handle_power_button(),
                .sleep_button => handle_sleep_button(),
            }
        }

        // Block until ISR signals new events (removes task from run queue)
        worker_wq.block_no_int(scheduler.get_current_task(), null);
        log.debug("worker woke up (head={d} tail={d})", .{ queue_head, queue_tail });
    }
}

// -- Event dispatch ----------------------------------------------------------

fn handle_gpe(gpe_num: u8) void {
    log.debug("GPE #{d} fired", .{gpe_num});

    // Build method name: _Exx (edge-triggered) or _Lxx (level-triggered)
    var name_buf: [4]u8 = undefined;

    // Try edge-triggered first (_Exx)
    name_buf = make_gpe_name('E', gpe_num);
    const gpe_scope = ns.root.find_child("_GPE".*) orelse {
        log.warn("GPE #{d}: no \\_GPE scope", .{gpe_num});
        return;
    };

    if (gpe_scope.find_child(name_buf)) |method_node| {
        evaluate_gpe_method(method_node, &name_buf);
        return;
    }

    // Try level-triggered (_Lxx)
    name_buf = make_gpe_name('L', gpe_num);
    if (gpe_scope.find_child(name_buf)) |method_node| {
        evaluate_gpe_method(method_node, &name_buf);
        return;
    }

    log.warn("GPE #{d}: no handler method found", .{gpe_num});
}

fn evaluate_gpe_method(method_node: *Node, name: *const [4]u8) void {
    log.debug("Evaluating \\_GPE.{s}", .{name});
    _ = executor.evaluate(ns, method_node, &.{}) catch |err| {
        log.err("\\_GPE.{s}: eval error: {s}", .{ name, @errorName(err) });
    };
}

fn handle_power_button() void {
    log.info("Power button pressed, initiating S5 shutdown", .{});
    @import("../../task/sleep.zig").sleep(500) catch {};
    @import("acpi.zig").power_off();
}

fn handle_sleep_button() void {
    log.info("Sleep button pressed (unhandled)", .{});
}

// -- GPE name helpers --------------------------------------------------------

fn make_gpe_name(prefix: u8, gpe_num: u8) [4]u8 {
    return .{
        '_',
        prefix,
        hex_char(gpe_num >> 4),
        hex_char(gpe_num & 0x0F),
    };
}

fn hex_char(v: u8) u8 {
    return if (v < 10) '0' + v else 'A' + v - 10;
}

fn parse_hex_pair(hi: u8, lo: u8) ?u8 {
    const h = hex_digit(hi) orelse return null;
    const l = hex_digit(lo) orelse return null;
    return (@as(u8, h) << 4) | l;
}

fn hex_digit(c: u8) ?u4 {
    if (c >= '0' and c <= '9') return @truncate(c - '0');
    if (c >= 'A' and c <= 'F') return @truncate(c - 'A' + 10);
    if (c >= 'a' and c <= 'f') return @truncate(c - 'a' + 10);
    return null;
}

// -- GPE discovery and enablement --------------------------------------------

fn discover_and_enable_gpes() void {
    const gpe_scope = ns.root.find_child("_GPE".*) orelse {
        log.warn("No \\_GPE scope found", .{});
        return;
    };

    var enable_mask: u16 = 0;
    var count: usize = 0;

    var child = gpe_scope.first_child;
    while (child) |c| {
        defer child = c.next_sibling;

        if (c.node_type != .method) continue;

        // Match _Exx or _Lxx pattern
        if (c.name[0] == '_' and (c.name[1] == 'E' or c.name[1] == 'L')) {
            const gpe_num = parse_hex_pair(c.name[2], c.name[3]) orelse continue;
            if (gpe_num < 16) {
                enable_mask |= @as(u16, 1) << @as(u4, @truncate(gpe_num));
                count += 1;
                log.debug("Found GPE handler: \\_GPE.{s} -> GPE #{d}", .{
                    @as(*const [4]u8, &c.name), gpe_num,
                });
            }
        }
    }

    if (count > 0) {
        // Clear any pending status before enabling
        write_gpe0_status(0xFFFF);
        write_gpe0_enable(enable_mask);
        log.info("Enabled {d} GPE handler(s) (mask=0x{X:0>4})", .{ count, enable_mask });
    }
}

// -- Notify handler registry -------------------------------------------------
//
// Per-node handlers take priority over the global fallback (§5.6.6).
// install_notify_handler(null, ...) registers a global handler.

pub const NotifyHandler = *const fn (node: *Node, value: u64, ctx: ?*anyopaque) void;

const HandlerEntry = struct {
    node: ?*Node, // null = global fallback
    handler: NotifyHandler,
    context: ?*anyopaque,
    active: bool,
};

const MAX_NOTIFY_HANDLERS = 128;
var notify_handlers: [MAX_NOTIFY_HANDLERS]HandlerEntry = [_]HandlerEntry{.{
    .node = null,
    .handler = undefined,
    .context = null,
    .active = false,
}} ** MAX_NOTIFY_HANDLERS;

/// Install a Notify handler for a specific node, or global if node is null.
pub fn install_notify_handler(
    node: ?*Node,
    handler: NotifyHandler,
    context: ?*anyopaque,
) !void {
    for (&notify_handlers) |*entry| {
        if (!entry.active) {
            entry.* = .{
                .node = node,
                .handler = handler,
                .context = context,
                .active = true,
            };
            return;
        }
    }
    return error.TooManyHandlers;
}

/// Remove a previously installed Notify handler.
pub fn remove_notify_handler(node: ?*Node, handler: NotifyHandler) void {
    for (&notify_handlers) |*entry| {
        if (entry.active and entry.node == node and entry.handler == handler) {
            entry.active = false;
            return;
        }
    }
}

/// Default global Notify handler — handles standard notification values.
fn default_notify_handler(node: *Node, value: u64, _: ?*anyopaque) void {
    var path_buf: [128]u8 = undefined;
    const path = node.full_path(&path_buf) catch "(unknown)";
    const val: u8 = @truncate(value);

    switch (val) {
        0x00 => {
            log.debug("Notify: Bus Check on {s}", .{path});
            rescan_device(ns, node, path);
        },
        0x01 => {
            log.debug("Notify: Device Check on {s}", .{path});
            rescan_device(ns, node, path);
        },
        0x02 => log.debug("Notify: Device Wake on {s}", .{path}),
        0x03 => {
            log.debug("Notify: Eject Request on {s}", .{path});
            handle_eject_request(ns, node, path);
        },
        else => log.debug("Notify: value=0x{X:0>2} on {s}", .{ val, path }),
    }
}

// -- Public API --------------------------------------------------------------

/// Initialize the ACPI event subsystem.
/// Must be called after namespace loading and ACPI mode enablement.
pub fn init(namespace: *Namespace) void {
    const Acpi = @import("acpi.zig");
    const fadt = Acpi.get_fadt() orelse {
        log.err("Cannot init events: no FADT", .{});
        return;
    };

    ns = namespace;

    // Cache port addresses from FADT (§4.8.1, §4.8.4)
    pm1a_sts_port = @truncate(fadt.pm1a_event_block);
    pm1a_en_port = @truncate(fadt.pm1a_event_block + fadt.pm1_event_length / 2);
    gpe0_sts_port = @truncate(fadt.gpe0_block);
    gpe0_en_port = @truncate(fadt.gpe0_block + fadt.gpe0_length / 2);

    log.debug("PM1a STS=0x{X}, EN=0x{X}", .{ pm1a_sts_port, pm1a_en_port });
    log.debug("GPE0 STS=0x{X}, EN=0x{X}", .{ gpe0_sts_port, gpe0_en_port });

    // Clear all pending events
    write_pm1_status(@bitCast(@as(u16, 0xFFFF)));
    write_gpe0_status(0xFFFF);

    // Disable all GPEs initially
    write_gpe0_enable(0);

    // Enable power button fixed event (§4.8.1.1)
    var pm1_en = read_pm1_enable();
    pm1_en.pwrbtn_en = true;
    write_pm1_enable(pm1_en);

    // Discover and enable GPEs that have handlers in the namespace
    discover_and_enable_gpes();

    // Install default global Notify handler
    install_notify_handler(null, &default_notify_handler, null) catch unreachable;

    // Register SCI interrupt handler (FADT.sci_interrupt = IRQ 9)
    const interrupts = @import("../../interrupts.zig");
    interrupts.set_intr_gate(
        pic.IRQ.ACPI,
        interrupts.Handler.create(&sci_handler, false),
    );
    pic.enable_irq(.ACPI);

    initialized = true;
    log.info("ACPI event subsystem initialized (SCI=IRQ{d})", .{fadt.sci_interrupt});
}

/// Spawn the ACPI worker kernel task.
/// Must be called after the scheduler and task caches are initialized.
pub fn start_worker() void {
    const task_set = @import("../../task/task_set.zig");
    const worker_task = task_set.create_task() catch {
        log.err("Failed to create ACPI worker task", .{});
        return;
    };
    worker_task.spawn(&acpi_worker, undefined) catch {
        log.err("Failed to spawn ACPI worker task", .{});
        return;
    };
    log.info("ACPI worker task spawned (pid={d})", .{worker_task.pid});
}

/// Dispatch an AML Notify(object, value) to the appropriate handler.
/// Called from the AML evaluator (term.zig) when a Notify opcode is executed.
///
/// Notification values (§5.6.6 Table 5.169):
///   0x00 = Bus Check       : re-enumerate child devices
///   0x01 = Device Check    : check if device appeared/disappeared
///   0x02 = Device Wake     : device has signalled wake
///   0x03 = Eject Request   : user requested eject
///   0x80+ = device-specific
///
/// Handler priority: per-node handler first, then global fallback.
pub fn dispatch_notify(_: *Namespace, node: *Node, value: u64) void {
    // 1. Try per-node handler
    for (notify_handlers) |entry| {
        if (entry.active and entry.node != null and entry.node == node) {
            entry.handler(node, value, entry.context);
            return;
        }
    }

    // 2. Fall back to global handler(s)
    for (notify_handlers) |entry| {
        if (entry.active and entry.node == null) {
            entry.handler(node, value, entry.context);
            return;
        }
    }

    // 3. No handler at all — log a warning
    var path_buf: [128]u8 = undefined;
    const path = node.full_path(&path_buf) catch "(unknown)";
    log.warn("Notify: no handler for value=0x{X:0>2} on {s}", .{ @as(u8, @truncate(value)), path });
}

/// Handle Bus Check / Device Check: re-evaluate _STA on children,
/// rescan PCI if the target is a PCI device or host bridge.
fn rescan_device(namespace: *Namespace, node: *Node, path: []const u8) void {
    // Re-evaluate _STA on the target node to get current status
    if (node.find_child("_STA".*)) |sta_node| {
        const result = executor.evaluate(namespace, sta_node, &.{}) catch |err| {
            log.warn("{s}._STA eval error: {s}", .{ path, @errorName(err) });
            return;
        };
        if (result.to_integer()) |val| {
            log.debug("{s}._STA = 0x{X:0>2}", .{ path, val });
        }
    }

    // Check if this is a PCI-related device that requires a bus rescan:
    // 1. Direct PCI host bridge (has _HID=PNP0A03 or _BBN)
    // 2. Child of a PCI host bridge (e.g., hotplug slot like \_SB.PCI0.S18)
    const needs_pci_rescan = is_pci_bridge(namespace, node) or is_pci_child(namespace, node);
    if (needs_pci_rescan) {
        log.debug("PCI device notified, rescanning PCI bus", .{});
        @import("../pci/pci.zig").rescan() catch |err| {
            log.warn("PCI rescan failed: {s}", .{@errorName(err)});
        };
    }

    // Re-enumerate ACPI devices to pick up new/removed ones
    @import("device.zig").enumerate(namespace);
}

/// Check if a node is a PCI host bridge (_HID=PNP0A03, _BBN, or _CID=PNP0A03).
fn is_pci_bridge(namespace: *Namespace, node: *Node) bool {
    if (node.find_child("_BBN".*) != null) return true;
    return is_pci_host(namespace, node);
}

/// Check if a node is a child of a PCI host bridge (e.g., a hotplug slot).
/// Also returns true if the node has _ADR (PCI address), indicating it's a PCI device.
fn is_pci_child(namespace: *Namespace, node: *Node) bool {
    // If the node has _ADR, it's likely a PCI device (slot)
    if (node.find_child("_ADR".*) != null) {
        // Verify parent is a PCI bridge
        if (node.parent) |parent| {
            if (is_pci_bridge(namespace, parent)) return true;
        }
    }

    // Walk up the tree to find a PCI host bridge ancestor
    var current = node.parent;
    while (current) |parent| {
        if (is_pci_bridge(namespace, parent)) return true;
        current = parent.parent;
    }
    return false;
}

/// Check if a node represents a PCI host bridge (_HID = "PNP0A03" or EISA equivalent).
fn is_pci_host(namespace: *Namespace, node: *Node) bool {
    const hid_node = node.find_child("_HID".*) orelse return false;

    switch (hid_node.object) {
        .string => |s| return std.mem.eql(u8, s, "PNP0A03"),
        .integer => |v| {
            // PNP0A03 as EISA ID = 0x030AD041
            return v == 0x030AD041;
        },
        .method => {
            const result = executor.evaluate(namespace, hid_node, &.{}) catch return false;
            switch (result) {
                .string => |s| return std.mem.eql(u8, s, "PNP0A03"),
                .integer => |v| return v == 0x030AD041,
                else => return false,
            }
        },
        else => return false,
    }
}

/// Handle Eject Request (Notify value 0x03): execute _EJ0 and rescan PCI.
/// Per ACPI spec §6.3.3, _EJ0 prepares the device for physical removal.
fn handle_eject_request(namespace: *Namespace, node: *Node, path: []const u8) void {
    // Check _STA first - if device is not present, nothing to eject
    if (node.find_child("_STA".*)) |sta_node| {
        const result = executor.evaluate(namespace, sta_node, &.{}) catch |err| {
            log.warn("{s}._STA eval error: {s}", .{ path, @errorName(err) });
            return;
        };
        if (result.to_integer()) |val| {
            const status: @import("device.zig").DeviceStatus = @bitCast(@as(u32, @truncate(val)));
            if (!status.present) {
                log.debug("{s}: device not present, skipping eject", .{path});
                return;
            }
        }
    }

    // Execute _EJ0 if it exists (tells hardware to eject)
    if (node.find_child("_EJ0".*)) |ej0_node| {
        log.debug("Executing {s}._EJ0", .{path});
        // _EJ0 takes one argument: the eject type (0 = cold eject, 1 = hot eject)
        _ = executor.evaluate(namespace, ej0_node, &.{.{ .integer = 1 }}) catch |err| {
            log.err("{s}._EJ0 failed: {s}", .{ path, @errorName(err) });
            return;
        };
    } else {
        log.warn("{s}: no _EJ0 method, cannot eject", .{path});
        return;
    }

    // Rescan PCI to remove the ejected device from our list
    if (is_pci_bridge(namespace, node) or is_pci_child(namespace, node)) {
        log.debug("PCI device ejected, rescanning PCI bus", .{});
        @import("../pci/pci.zig").rescan() catch |err| {
            log.warn("PCI rescan failed: {s}", .{@errorName(err)});
        };
    }

    // Re-enumerate ACPI devices
    @import("device.zig").enumerate(namespace);
}
