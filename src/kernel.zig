const keyboard = @import("./tty/keyboard.zig");
const printk = @import("./tty/tty.zig").printk;
const shell = @import("./shell.zig").shell;
const paging = @import("memory/paging.zig");

pub fn main() void {
    printk("hello, \x1b[32m{d}\x1b[0m\n", .{42});
    printk("a = alloc(1)\n", .{});
    var a = @import("memory.zig").virtualPageAllocator.alloc_pages(1) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    printk("a: 0x{x:0>8}\n", .{@intFromPtr(a)});
    printk("b = alloc(16)\n", .{});
    var b = @import("memory.zig").virtualPageAllocator.alloc_pages(16) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    printk("b: 0x{x:0>8}\n", .{@intFromPtr(b)});

    printk("free(a)\n", .{});
    @import("memory.zig").virtualPageAllocator.free_pages(a, 1) catch unreachable;
    printk("c = alloc(1)\n", .{});
    var c = @import("memory.zig").virtualPageAllocator.alloc_pages(1) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    printk("c: 0x{x:0>8}\n", .{@intFromPtr(c)});
    printk("free(b)\n", .{});
    @import("memory.zig").virtualPageAllocator.free_pages(b, 16) catch unreachable;
    printk("free(c)\n", .{});
    @import("memory.zig").virtualPageAllocator.free_pages(c, 1) catch unreachable;

    printk("a = alloc(1)\n", .{});
    a = @import("memory.zig").virtualPageAllocator.alloc_pages(1) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    printk("b = alloc(16)\n", .{});
    b = @import("memory.zig").virtualPageAllocator.alloc_pages(16) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    printk("a: 0x{x:0>8}\n", .{@intFromPtr(a)});
    printk("b: 0x{x:0>8}\n", .{@intFromPtr(b)});

    printk("free(a)\n", .{});
    @import("memory.zig").virtualPageAllocator.free_pages(a, 1) catch unreachable;
    printk("c = alloc(1, kernelspace)\n", .{});
    c = @import("memory.zig").virtualPageAllocator.alloc_pages_opt(1, .{.type = .KernelSpace}) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    printk("c: 0x{x:0>8}\n", .{@intFromPtr(c)});
    printk("a = alloc(1)\n", .{});
    a = @import("memory.zig").virtualPageAllocator.alloc_pages(1) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    printk("a: 0x{x:0>8}\n", .{@intFromPtr(a)});
    printk("free(c)\n", .{});
    @import("memory.zig").virtualPageAllocator.free_pages(c, 1) catch unreachable;
    printk("c = alloc(1, kernelspace)\n", .{});
    c = @import("memory.zig").virtualPageAllocator.alloc_pages_opt(1, .{.type = .KernelSpace}) catch @as(paging.VirtualPagePtr, @ptrFromInt(0));
    printk("c: 0x{x:0>8}\n", .{@intFromPtr(c)});

    _ = shell();
}
