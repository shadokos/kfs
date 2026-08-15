// What happens to bytes between the hardware and a read. Canonical mode gathers
// them into lines a user can correct; echo, erase and kill live here, POSIX
// 11.1.6 and 11.1.9. A module rather than a table of function pointers, there
// being one discipline to choose from.

const std = @import("std");

const TtyStruct = @import("../TtyStruct.zig");
const termios = @import("../termios.zig");

fn cc(tty: *const TtyStruct, comptime which: termios.cc_index) u8 {
    return tty.config.c_cc[@intFromEnum(which)];
}

// Input

/// Run bytes arriving from the hardware through the discipline.
pub fn receive(tty: *TtyStruct, s: []const u8) void {
    for (s) |c| receive_char(tty, c);
    // Echo reached the driver as it went; nothing has told it to show what it
    // accumulated yet.
    tty.driver_flush();
    tty.read_queue.try_unblock();
}

fn receive_char(tty: *TtyStruct, raw: u8) void {
    const c = input_processing(tty, raw) orelse return;

    if (!tty.config.c_lflag.ICANON) {
        // Nothing is being edited, so a byte is readable as soon as it lands.
        tty.input_buffer.push(c);
        tty.input_buffer.commit();
        echo(tty, c);
        return;
    }

    if (is_end_of_line(tty, c)) {
        // Kept, so read() can tell a line ended by EOF from one ended by a
        // newline.
        if (c != cc(tty, .VEOF)) echo(tty, c);
        tty.input_buffer.push(c);
        tty.input_buffer.commit();
    } else if (c == cc(tty, .VERASE)) {
        erase_char(tty);
    } else if (c == cc(tty, .VKILL)) {
        kill_line(tty);
    } else {
        tty.input_buffer.push(c);
        echo(tty, c);
    }
}

/// POSIX input modes, c_iflag, POSIX 11.2.2.
fn input_processing(tty: *TtyStruct, raw: u8) ?u8 {
    const c = if (tty.config.c_iflag.ISTRIP) raw & 0x7f else raw;

    if (tty.config.c_iflag.IGNCR and c == '\r') return null;
    if (tty.config.c_iflag.ICRNL and c == '\r') return '\n';
    if (tty.config.c_iflag.INLCR and c == '\n') return '\r';
    return c;
}

fn is_end_of_line(tty: *const TtyStruct, c: u8) bool {
    return c == '\n' or c == cc(tty, .VEOL) or c == cc(tty, .VEOF);
}

/// Whether ECHOCTL should show this byte as ^X rather than send it through.
fn is_echoctl(tty: *const TtyStruct, c: u8) bool {
    return c & 0b11100000 == 0 and
        c != '\t' and
        c != '\n' and
        c != cc(tty, .VSTART) and
        c != cc(tty, .VSTOP);
}

/// Take one character back off the line being edited, and unprint it. One shown
/// as ^X took two columns, so it takes two to rub out. Erase stops at the start
/// of the line, POSIX 11.1.6.
fn erase_char(tty: *TtyStruct) void {
    const erased = tty.input_buffer.erase() orelse return;
    if (!(tty.config.c_lflag.ECHO and tty.config.c_lflag.ECHOE)) return;

    tty.output("\x08 \x08");
    if (tty.config.c_lflag.ECHOCTL and is_echoctl(tty, erased))
        tty.output("\x08 \x08");
}

/// Throw away the line being edited, POSIX 11.1.9. POSIX only asks that ECHOK
/// echo a newline; rubbing the line out instead is what ECHOE already does for
/// one character, so it is kept when ECHOE is set.
fn kill_line(tty: *TtyStruct) void {
    if (tty.config.c_lflag.ECHO and tty.config.c_lflag.ECHOE) {
        while (tty.input_buffer.head != tty.input_buffer.canon_head) erase_char(tty);
        return;
    }

    tty.input_buffer.head = tty.input_buffer.canon_head;
    if (tty.config.c_lflag.ECHO and tty.config.c_lflag.ECHOK) tty.output("\n");
}

/// Show a character as it is typed, POSIX 11.2.5. Echo goes through output
/// processing like a write, or the line after a typed newline starts under
/// wherever the typing stopped.
fn echo(tty: *TtyStruct, c: u8) void {
    if (tty.config.c_lflag.ECHO or (c == '\n' and tty.config.c_lflag.ECHONL)) {
        if (tty.config.c_lflag.ECHOCTL and is_echoctl(tty, c)) {
            tty.output(&[2]u8{ '^', c | 0b01000000 });
        } else {
            tty.output(&[1]u8{c});
        }
    }
}

// Reading

/// Whether a read can be satisfied right now. A canonical read may only reach
/// a completed line, POSIX 11.1.6.
pub fn has_input(tty: *const TtyStruct) bool {
    return if (tty.config.c_lflag.ICANON)
        tty.input_buffer.canon_count() != 0
    else
        tty.input_buffer.count() != 0;
}

/// Hand bytes to a reader, waiting until the discipline has some.
///
/// VMIN and VTIME are not honoured yet, so a read returns on a complete line in
/// canonical mode and on the first byte otherwise.
pub fn read(tty: *TtyStruct, s: []u8) usize {
    const scheduler = @import("../../task/scheduler.zig");
    var count: usize = 0;

    for (s) |*c| {
        while (!has_input(tty))
            tty.read_queue.block_no_int(scheduler.get_current_task(), @ptrCast(tty));

        const byte = tty.input_buffer.pop().?;
        c.* = byte;
        count += 1;

        if (tty.config.c_lflag.ICANON and is_end_of_line(tty, byte)) {
            // Not part of the line. A line holding only EOF gives a read of
            // zero, which is how a terminal reports end of input.
            if (byte == cc(tty, .VEOF)) count -= 1;
            break;
        }
    }
    return count;
}
