const std = @import("std");

const vfs = @import("../../fs/vfs.zig");
const File = @import("../../fs/file.zig");
const TtyStruct = @import("../../tty/TtyStruct.zig");
const serial = @import("../../drivers/tty/serial.zig");
const tty_cdev = @import("../../drivers/tty/tty_cdev.zig");

pub const Shell = @import("../Shell.zig").Shell(@import("builtins.zig"));

const path = "/dev/ttyS0";

/// The line the CI talks over, reached the way a program would.
///
/// Before the shell has opened it, and for a panic reporting from there, writes
/// go straight to the terminal: the descriptor needs a mounted devfs, the
/// terminal only needs the port to have been found.
pub var line: Line = .{};

pub const Line = struct {
    file: ?*File = null,

    /// The protocol is delimited by newlines, and formatting a packet reaches
    /// the writer a few bytes at a time. Gathering a line before handing it
    /// over keeps each fragment from crossing the whole stack on its own.
    buffer: [512]u8 = undefined,
    used: usize = 0,

    pub const ReadError = File.Error.read;
    pub const WriteError = File.Error.write;
    pub const Reader = std.io.GenericReader(*Line, ReadError, read);
    pub const Writer = std.io.GenericWriter(*Line, WriteError, write);

    fn terminal(self: *Line) ?*TtyStruct {
        if (self.file) |f| return tty_cdev.terminal_of(f);
        return serial.first_line();
    }

    fn read(self: *Line, buffer: []u8) ReadError!usize {
        const f = self.file orelse return error.ENODEV;
        return f.read(buffer);
    }

    pub fn write(self: *Line, bytes: []const u8) WriteError!usize {
        for (bytes) |c| {
            self.buffer[self.used] = c;
            self.used += 1;
            if (c == '\n' or self.used == self.buffer.len) try self.flush();
        }
        return bytes.len;
    }

    fn flush(self: *Line) WriteError!void {
        const out = self.buffer[0..self.used];
        self.used = 0;
        if (out.len == 0) return;

        if (self.file) |f| {
            _ = try f.write(out);
        } else if (self.terminal()) |t| {
            _ = t.write(out) catch {};
        }
    }

    pub fn get_reader(self: *Line) Reader {
        return .{ .context = self };
    }

    pub fn get_writer(self: *Line) Writer {
        return .{ .context = self };
    }

    /// Send what is held without waiting for an interrupt, for the panic path.
    pub fn flush_sync(self: *Line) void {
        self.flush() catch {};
        const t = self.terminal() orelse return;
        serial.flush_sync(t);
    }
};

pub fn on_init(shell: *Shell) void {
    const tnode = vfs.resolve(path) catch
        return std.log.err("CI: cannot resolve " ++ path, .{});
    defer tnode.release();

    line.file = tnode.inode.open() catch
        return std.log.err("CI: cannot open " ++ path, .{});

    const terminal = tty_cdev.terminal_of(line.file.?) orelse
        return std.log.err("CI: " ++ path ++ " is not a terminal", .{});

    // A protocol, not a person: nothing to echo back, no newline to translate,
    // and a byte of payload must not be read as a signal or as flow control.
    var config = terminal.config;
    config.c_iflag = .{};
    config.c_oflag = .{};
    config.c_lflag = .{ .ICANON = true };
    terminal.set_termios(config);

    _ = shell.writer.write("CI on " ++ path ++ "\n") catch {};
}

pub fn on_error(shell: *Shell) void {
    const err = shell.execution_context.err orelse unreachable;

    var packet = @import("packet.zig").Packet(void).init(shell.writer);
    packet.err = err;
    packet.send();
}
