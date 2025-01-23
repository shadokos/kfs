const cpu = @import("../../cpu.zig");
const ft = @import("ft");

/// screen width
pub const width = 80;
/// screen height
pub const height = 25;

pub const Color = packed struct(u24) {
    b: u8,
    g: u8,
    r: u8,
    /// convert from web color format to Color
    pub fn convert(web: u24) Color {
        var ret: Color = @bitCast(web);
        ret.r = (ret.r >> 2) + ((ret.r >> 1) & 1);
        ret.g = (ret.g >> 2) + ((ret.g >> 1) & 1);
        ret.b = (ret.b >> 2) + ((ret.b >> 1) & 1);
        if (ret.r == 64) ret.r = 63;
        if (ret.g == 64) ret.g = 63;
        if (ret.b == 64) ret.b = 63;
        return ret;
    }
};

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
        _ = cpu.inb(0x3da);
        cpu.outb(0x3c0, @intCast(i));
        cpu.outb(0x3c8, cpu.inb(0x3c1));
        cpu.outb(0x3c9, c.r);
        cpu.outb(0x3c9, c.g);
        cpu.outb(0x3c9, c.b);
        _ = cpu.inb(0x3da);
        cpu.outb(0x3c0, 0x20);
    }
}
