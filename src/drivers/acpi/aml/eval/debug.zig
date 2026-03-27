/// DebugObj store target (ACPI 6.4 §20.2.6.3, §19.6.26).
///
/// DebugObj := DebugOp
/// DebugOp  := ExtOpPrefix 0x31
///
/// "When a value is stored to the Debug object, the data is sent to the
/// kernel debugging port" (§19.6.26).
const std = @import("std");
const objects = @import("../objects.zig");

const Object = objects.Object;
const log = std.log.scoped(.acpi_exec);

/// Log a value written to the Debug object.
pub fn log_debug_store(value: Object) void {
    switch (value) {
        .integer => |v| log.debug("Debug: 0x{x}", .{v}),
        .string => |s| log.debug("Debug: \"{s}\"", .{s}),
        .buffer => |b| log.debug("Debug: Buffer({d})", .{b.data.len}),
        .uninitialized => log.debug("Debug: <uninitialized>", .{}),
        else => log.debug("Debug: [{s}]", .{@tagName(value)}),
    }
}
