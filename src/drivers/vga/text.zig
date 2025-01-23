const cpu = @import("../../cpu.zig");
const ft = @import("ft");
const config = @import("config");

/// screen width
pub const width = 80;
/// screen height
pub const height = 25;

pub const Color = @import("colors").LAB(config.theme.profile);

/// A vga color palette
pub const Palette = [16]Color;

/// whether or not the cursor is on the screen
var cursor_enabled: bool = false;

/// address of the mmio vga buffer
const mmio_buffer: [*]u16 = @ptrFromInt(@import("../../memory/paging.zig").high_half + 0xB8000);

pub fn put_char(line: usize, col: usize, char: u16) void {
    mmio_buffer[line * width + col] = char;
}

/// enable the cursor
pub fn enable_cursor() void {
    if (cursor_enabled)
        return;
    const cursor_start: u8 = 0;
    const cursor_end: u8 = 15;
    cpu.outb(.vga_idx_reg, 0x0A);
    cpu.outb(.vga_io_reg, (cpu.inb(.vga_io_reg) & 0xC0) | cursor_start);
    cpu.outb(.vga_idx_reg, 0x0B);
    cpu.outb(.vga_io_reg, (cpu.inb(.vga_io_reg) & 0xE0) | cursor_end);
    cursor_enabled = true;
}

/// disable the cursor
pub fn disable_cursor() void {
    if (!cursor_enabled)
        return;
    cpu.outb(.vga_idx_reg, 0x0A);
    cpu.outb(.vga_io_reg, 0x20);
    cursor_enabled = false;
}

/// set cursor pos
pub fn set_cursor_pos(x: u8, y: u8) void {
    const index: u32 = @as(u32, @intCast(y)) * width + @as(u32, @intCast(x));
    cpu.outb(.vga_idx_reg, 0x0F);
    cpu.outb(.vga_io_reg, @intCast(index & 0xff));
    cpu.outb(.vga_idx_reg, 0x0E);
    cpu.outb(.vga_io_reg, @intCast((index >> 8) & 0xff));
}

/// set the color palette
pub fn set_palette(palette: Palette) void {
    for (palette, 0..) |c, i| {
        const vga_color = c.to_vga();

        _ = cpu.inb(0x3da);
        cpu.outb(0x3c0, @intCast(i));
        cpu.outb(0x3c8, cpu.inb(0x3c1));
        cpu.outb(0x3c9, vga_color.r);
        cpu.outb(0x3c9, vga_color.g);
        cpu.outb(0x3c9, vga_color.b);
        _ = cpu.inb(0x3da);
        cpu.outb(0x3c0, 0x20);
    }
}
