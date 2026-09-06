const std = @import("std");
pub const Id = 25;
const Errno = @import("../errno.zig").Errno;
const vfs = @import("../fs/vfs.zig");
const TNode = @import("../fs/tnode.zig");
const INode = @import("../fs/inode.zig");
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
const sysv = @import("../task/sysv.zig");

const allocator = @import("../memory.zig").smallAlloc.allocator();

// Every entry costs at least one pointer word in the sysv entry block, so arg_max
// already bounds how many we can ever accept. exec() checks the strings themselves.
const max_entries = sysv.arg_max / @sizeOf(usize);

/// Walk a NULL terminated userspace pointer array into a kernel side slice of slices.
/// The strings are left in place, exec() copies them before the address space swap.
fn collect(arr: [*:null]const ?[*:0]const u8) Errno![]const []const u8 {
    var len: usize = 0;
    while (arr[len] != null) : (len += 1) {
        if (len == max_entries) return Errno.E2BIG;
    }

    const out = allocator.alloc([]const u8, len) catch return Errno.ENOMEM;
    for (out, 0..) |*slot, i| slot.* = std.mem.span(arr[i].?);
    return out;
}

pub fn do(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) Errno!void {
    const tnode = try vfs.resolve(std.mem.span(path));
    errdefer tnode.release();

    const argv_slices = try collect(argv);
    errdefer allocator.free(argv_slices);
    const envp_slices = try collect(envp);
    errdefer allocator.free(envp_slices);

    const req = try TaskDescriptor.prepare_exec(tnode.inode, argv_slices, envp_slices);

    // Nothing can fail past this point, and commit_exec does not come back: it resets the
    // kernel stack this frame lives on. Release what we own now, no defer would ever run.
    allocator.free(envp_slices);
    allocator.free(argv_slices);
    tnode.release();

    scheduler.get_current_task().commit_exec(req);
}
