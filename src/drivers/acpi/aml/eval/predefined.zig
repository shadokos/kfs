/// Built-in predefined method implementations (ACPI 6.4 §5.7).
///
/// These methods are created during namespace initialization with empty
/// code slices (code.len == 0). When invoked, they are intercepted before
/// normal method execution and dispatched here.
///
/// Currently implemented:
///   \_OSI  — Operating System Interface query (§5.7.2)
const std = @import("std");
const objects = @import("../objects.zig");
const node_mod = @import("../../namespace/node.zig");

const Object = objects.Object;
const Node = node_mod.Node;

/// Dispatch a built-in method by node name.
/// Returns null if the node is not a known built-in.
pub fn dispatch(node: *Node, args: []const Object) ?Object {
    if (std.mem.eql(u8, &node.name, "_OSI")) {
        return eval_osi(if (args.len > 0) args[0] else .uninitialized);
    }
    return null;
}

/// \_OSI: Operating System Interface (§5.7.2).
///
/// Accepts one String argument naming an OS interface.
/// Returns Ones (0xFFFFFFFF = True) if supported, Zero (0 = False) otherwise.
///
/// We report compatibility with common Windows versions and Linux to
/// maximize real-world DSDT table compatibility.
fn eval_osi(arg: Object) Object {
    const iface = switch (arg) {
        .string => |s| s,
        else => return .{ .integer = 0 },
    };

    const supported = [_][]const u8{
        "Windows 2000",
        "Windows 2001", // XP
        "Windows 2001 SP1",
        "Windows 2001.1", // Server 2003
        "Windows 2001 SP2",
        "Windows 2006", // Vista
        "Windows 2006.1", // Server 2008
        "Windows 2006 SP1",
        "Windows 2006 SP2",
        "Windows 2009", // 7
        "Windows 2012", // 8
        "Windows 2013", // 8.1
        "Windows 2015", // 10
        "Linux",
    };

    for (supported) |s| {
        if (iface.len == s.len and std.mem.eql(u8, iface, s)) {
            return .{ .integer = 0xFFFFFFFF };
        }
    }
    return .{ .integer = 0 };
}
