const std = @import("std");
pub const Id = 25;
const Errno = @import("../errno.zig").Errno;
const vfs = @import("../fs/vfs.zig");
const TNode = @import("../fs/tnode.zig");
const INode = @import("../fs/inode.zig");
const File = @import("../fs/file.zig");
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

fn is_interpreted(tnode : *TNode) Errno!bool {
    var buffer : [2]u8 = undefined;
    var file = try tnode.inode.open();
    const ret = try file.pread(0, buffer[0..2]) == 2 and
        std.mem.eql(u8, buffer[0..2], "#!");
    try file.close();
    return ret;
}

fn get_interpreter_args(tnode : *TNode, buffer : []u8, path : [*:0]const u8, base_argv : []const []const u8) Errno![][]const u8 {
    const file = try tnode.inode.open();
    const size = try file.pread(2, buffer[0..]);
    const slice = buffer[0..size];
    const line = std.mem.sliceTo(slice, '\n');

    var args :std.ArrayList([]const u8) = .{};
    errdefer allocator.free(args.items);

    var iterator = std.mem.splitScalar(u8, line, ' ');
    while (iterator.next()) |arg| {
        (args.addOne(allocator) catch return Errno.ENOMEM).* = arg;
    }
    (args.addOne(allocator) catch return Errno.ENOMEM).* = std.mem.span(path);
    @memcpy(args.addManyAsSlice(allocator, base_argv.len) catch return Errno.ENOMEM, base_argv);
    allocator.free(base_argv);
    return args.items;
}

pub fn do(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) Errno!void {
    std.log.debug("a", .{});
    var buffer :[100]u8 = undefined;
    const tnode = try vfs.resolve(std.mem.span(path));
    errdefer tnode.release();
    std.log.debug("b", .{});

    var argv_slices = try collect(argv);
    errdefer allocator.free(argv_slices);
    const envp_slices = try collect(envp);
    errdefer allocator.free(envp_slices);

    var inode = tnode.inode.get_ref();
    if (try is_interpreted(tnode)) {
        std.log.debug("c", .{});
        argv_slices = try get_interpreter_args(tnode, buffer[0..], path, argv_slices,);
        std.log.debug("d", .{});
        const interpreter_tnode = try vfs.resolve(argv_slices[0]);
        std.log.debug("e", .{});
        inode = interpreter_tnode.inode.get_ref();
        interpreter_tnode.release();
    }

    std.log.debug("f", .{});
    const req = try TaskDescriptor.prepare_exec(inode, argv_slices, envp_slices);
    std.log.debug("g", .{});

    // Nothing can fail past this point, and commit_exec does not come back: it resets the
    // kernel stack this frame lives on. Release what we own now, no defer would ever run.
    allocator.free(envp_slices);
    allocator.free(argv_slices);
    tnode.release();
    inode.release();

    scheduler.get_current_task().commit_exec(req);
}
