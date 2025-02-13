const tty = @import("tty/tty.zig");
const c = @import("colors");

const logo = @embedFile("misc/ascii_art/logo.ascii");
const letter_o = @embedFile("misc/ascii_art/letters/o.ascii");
const letter_h = @embedFile("misc/ascii_art/letters/h.ascii");
const letter_n = @embedFile("misc/ascii_art/letters/n.ascii");

const letter_exclamation = @embedFile("misc/ascii_art/letters/exclamation_mark.ascii");

pub fn print_ascii_art(
    image: []const u8,
    coord: struct { x: u16, y: u16 },
    colors: struct { bg: []const u8, fg: []const u8 },
) void {
    var _coord = coord;
    tty.printk("\x1b[2m\x1b[37m{s}{s}", .{ colors.bg, colors.fg });
    for (image) |char| switch (char) {
        ' ' => _coord.x += 1,
        '\n' => {
            _coord.x = coord.x;
            _coord.y += 1;
        },
        else => {
            if (_coord.x >= 80 or _coord.y >= 25)
                continue;
            tty.printk(
                "\x1b[{d};{d}H{s}",
                .{ _coord.y, _coord.x, [1]u8{char} },
            );
            _coord.x += 1;
        },
    };
}

pub fn screen_of_death(comptime format: []const u8, args: anytype) void {
    tty.printk(c.bg_red ++ "{s}", .{(" " ** (tty.width * tty.height))});
    tty.get_tty().scroll(1);
    print_ascii_art(logo, .{ .x = 37, .y = 0 }, .{ .bg = c.bg_red, .fg = c.white });
    print_ascii_art(letter_o, .{ .x = 3, .y = 2 }, .{ .bg = c.bg_black, .fg = c.black ++ c.dim });
    print_ascii_art(letter_h, .{ .x = 10, .y = 2 }, .{ .bg = c.bg_black, .fg = c.black ++ c.dim });
    print_ascii_art(letter_n, .{ .x = 21, .y = 2 }, .{ .bg = c.bg_black, .fg = c.black ++ c.dim });
    print_ascii_art(letter_o, .{ .x = 28, .y = 2 }, .{ .bg = c.bg_black, .fg = c.black ++ c.dim });
    print_ascii_art(letter_exclamation, .{ .x = 33, .y = 2 }, .{ .bg = c.bg_black, .fg = c.black ++ c.dim });
    tty.printk("\x1b[9;3H" ++ c.black ++ c.bg_red ++ "{s}", .{"######## KERNEL PANIC! #########"});
    tty.printk("\x1b[11;3H" ++ c.reset ++ c.white ++ c.bg_red, .{});
    tty.printk(format, args);
}
