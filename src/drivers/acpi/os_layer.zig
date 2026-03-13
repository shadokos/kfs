/// ACPI OS Layer
///
/// This module provides the OS-specific implementations of the functions required by the ACPI subsystem. It includes:
/// - I/O port access (read/write)
/// - Physical memory mapping (map/unmap)
/// - Object allocation (kmalloc/kfree)
/// - Timing delays (stall_us/stall_ms)
///
const std = @import("std");
const cpu = @import("../../cpu.zig");
const timer = @import("../../timer.zig");

const log = std.log.scoped(.@"acpi(osl)");

// IO port access ------------------------------------------------------------
//
pub fn read_io(port: u16, comptime width: u8) IoResult(width) {
    return switch (width) {
        1 => cpu.inb(port),
        2 => cpu.inw(port),
        4 => cpu.inl(port),
        else => @compileError("read_io: unsupported width"),
    };
}

pub fn write_io(port: u16, comptime width: u8, val: IoResult(width)) void {
    switch (width) {
        1 => cpu.outb(port, val),
        2 => cpu.outw(port, val),
        4 => cpu.outl(port, val),
        else => @compileError("write_io: unsupported width"),
    }
}

fn IoResult(comptime width: u8) type {
    return switch (width) {
        1 => u8,
        2 => u16,
        4 => u32,
        else => @compileError("unsupported I/O width"),
    };
}

// Physical memory mapping ---------------------------------------------------
//
pub fn map_memory(phys: u32, size: usize) ![*]align(1) u8 {
    const memory = @import("../../memory.zig");
    return @ptrCast(
        memory.kernel_virtual_space.map_object_anywhere(phys, size) catch |e| {
            log.err("Failed to map physical 0x{x} size 0x{x}: {s}", .{ phys, size, @errorName(e) });
            return e;
        },
    );
}

pub fn unmap_memory(virt: [*]align(1) u8, size: usize) void {
    const memory = @import("../../memory.zig");
    memory.kernel_virtual_space.unmap_object(@ptrCast(virt), size) catch |e| {
        log.warn("Failed to unmap 0x{x} size 0x{x}: {s}", .{ @intFromPtr(virt), size, @errorName(e) });
    };
}

pub fn map_object(comptime T: type, phys: u32) !*align(1) T {
    const ptr = try map_memory(phys, @sizeOf(T));
    return @ptrCast(ptr);
}

// Object allocation ---------------------------------------------------------
//
pub fn kmalloc(comptime T: type, n: usize) ?[]T {
    const memory = @import("../../memory.zig");
    return memory.smallAlloc.alloc(T, n) catch return null;
}

pub fn kfree(ptr: anytype) void {
    const memory = @import("../../memory.zig");
    memory.smallAlloc.free(ptr);
}

// Timing delays -------------------------------------------------------------
//
pub fn stall_us(us: u64) void {
    timer.busy_usleep(us);
}

pub fn stall_ms(ms: u64) void {
    timer.busy_sleep(ms);
}
