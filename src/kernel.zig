const keyboard = @import("./tty/keyboard.zig");
const printk = @import("./tty/tty.zig").printk;
const shell = @import("./shell.zig").shell;
const paging = @import("memory/paging.zig");

pub fn main() void {
    printk("hello, \x1b[32m{d}\x1b[37m\n", .{42});
    var a = @import("memory.zig").virtualPageAllocator.alloc_pages(1) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    const pa : *u32 = @ptrCast(@alignCast(a));
    pa.* = 42;
    var b = @import("memory.zig").virtualPageAllocator.alloc_pages(16) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));

    @import("memory.zig").virtualPageAllocator.free_pages(a, 1);
    var c = @import("memory.zig").virtualPageAllocator.alloc_pages(1) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    printk("a: {d}\n", .{pa.*});
    printk("a = alloc(1)\n", .{});
    printk("b = alloc(16)\n", .{});
    printk("a: 0x{x:0>8}\n", .{@intFromPtr(a)});
    printk("b: 0x{x:0>8}\n", .{@intFromPtr(b)});
    printk("free(a)\n", .{});
    printk("c = alloc(1)\n", .{});
    printk("c: 0x{x:0>8}\n", .{@intFromPtr(c)});
    printk("free(b)\n", .{});
    @import("memory.zig").virtualPageAllocator.free_pages(b, 16);
    printk("free(c)\n", .{});
    @import("memory.zig").virtualPageAllocator.free_pages(c, 1);

    printk("a = alloc(1)\n", .{});
    a = @import("memory.zig").virtualPageAllocator.alloc_pages(1) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    printk("b = alloc(16)\n", .{});
    b = @import("memory.zig").virtualPageAllocator.alloc_pages(16) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    printk("a: 0x{x:0>8}\n", .{@intFromPtr(a)});
    printk("b: 0x{x:0>8}\n", .{@intFromPtr(b)});

    printk("free(a)\n", .{});
    @import("memory.zig").virtualPageAllocator.free_pages(a, 1);
    printk("c = alloc(1)\n", .{});
    c = @import("memory.zig").virtualPageAllocator.alloc_pages(1) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    printk("c: 0x{x:0>8}\n", .{@intFromPtr(c)});

    _ = shell();
}
