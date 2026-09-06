// What happens to bytes between the hardware and a read. Canonical mode gathers
// them into lines a user can correct; echo, erase and kill live here, POSIX
// 11.1.6 and 11.1.9. A module rather than a table of function pointers, there
// being one discipline to choose from.

const std = @import("std");

const TtyStruct = @import("../TtyStruct.zig");
const termios = @import("../termios.zig");
const scheduler = @import("../../task/scheduler.zig");
const timer = @import("../../timer.zig");
const TaskDescriptor = @import("../../task/task.zig").TaskDescriptor;
const signal = @import("../../task/signal.zig");
const task_set = @import("../../task/task_set.zig");

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

/// The signal a control character raises, or null when it raises none.
/// A c_cc entry left at zero disables that character, POSIX 11.1.9.
fn signal_char(tty: *const TtyStruct, c: u8) ?signal.Id {
    if (!tty.config.c_lflag.ISIG) return null;

    const generators = .{
        .{ termios.cc_index.VINTR, signal.Id.SIGINT },
        .{ termios.cc_index.VQUIT, signal.Id.SIGQUIT },
        .{ termios.cc_index.VSUSP, signal.Id.SIGTSTP },
    };
    inline for (generators) |generator| {
        const wanted = tty.config.c_cc[@intFromEnum(generator[0])];
        if (wanted != 0 and c == wanted) return generator[1];
    }
    return null;
}

/// Raise a signal on the group holding the terminal, POSIX 11.1.9.
///
/// The half typed line goes with it unless NOFLSH says otherwise: whatever was
/// being edited was meant for a job that is about to be interrupted.
fn raise_signal(tty: *TtyStruct, c: u8, id: signal.Id) void {
    echo(tty, c);
    if (!tty.config.c_lflag.NOFLSH) tty.input_buffer.clear();

    const pgid = tty.foreground_pgid orelse return;
    _ = task_set.send_signal_to_group(pgid, .{
        .si_signo = .{ .valid = id },
        .si_code = .SI_KERNEL,
        .si_pid = 0,
    });
}

/// The START and STOP characters, POSIX 11.2.2 IXON. They control output and
/// are not themselves input, so they never reach a reader.
///
/// IXANY makes any character restart output, which is what makes a terminal
/// frozen by a stray Ctrl-S recoverable by typing anything at all.
fn flow_control(tty: *TtyStruct, c: u8) bool {
    if (!tty.config.c_iflag.IXON) return false;

    if (c == cc(tty, .VSTOP)) {
        tty.set_output_stopped(true);
        return true;
    }
    if (c == cc(tty, .VSTART)) {
        tty.set_output_stopped(false);
        return true;
    }
    if (tty.output_stopped and tty.config.c_iflag.IXANY) {
        tty.set_output_stopped(false);
        return true;
    }
    return false;
}

fn receive_char(tty: *TtyStruct, raw: u8) void {
    const c = input_processing(tty, raw) orelse return;

    if (flow_control(tty, c)) return;
    if (signal_char(tty, c)) |id| return raise_signal(tty, c, id);

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

/// VTIME counts tenths of a second.
const vtime_unit_us = 100_000;

fn read_timed_out(_: *TaskDescriptor, data: *usize) void {
    const tty: *TtyStruct = @ptrCast(@alignCast(data));
    tty.read_timed_out = true;
    tty.read_queue.try_unblock();
}

fn arm_timer(tty: *TtyStruct, deciseconds: u8) ?u64 {
    tty.read_timed_out = false;
    return timer.schedule_event(.{
        .timestamp = timer.get_utime_since_boot() + @as(u64, deciseconds) * vtime_unit_us,
        .callback = read_timed_out,
        .task = scheduler.get_current_task(),
        .data = @ptrCast(@alignCast(tty)),
    }) catch null;
}

/// Sleep until the discipline publishes something or VTIME runs out. A stop
/// pauses the read on this stack rather than ending it.
fn wait(tty: *TtyStruct) TtyStruct.ReadError!void {
    const task = scheduler.get_current_task();

    while (true) {
        tty.read_queue.block(task, @ptrCast(tty)) catch {};

        // Input beats a signal that is only waiting.
        if (tty.read_timed_out or has_input(tty)) return;

        switch (task.pending_disposition()) {
            .stop => task.stop_in_place(),
            .interrupt => return error.EINTR,
            // Woken by nothing in particular; wait again.
            .none => {},
        }
    }
}

/// Hand bytes to a reader. Canonical mode ignores VMIN and VTIME: a line is the
/// unit, and is not readable until finished, POSIX 11.1.6.
pub fn read(tty: *TtyStruct, s: []u8) TtyStruct.ReadError!usize {
    if (s.len == 0) return 0;
    return if (tty.config.c_lflag.ICANON)
        read_canonical(tty, s)
    else
        read_raw(tty, s);
}

fn read_canonical(tty: *TtyStruct, s: []u8) TtyStruct.ReadError!usize {
    var count: usize = 0;

    for (s) |*c| {
        while (!has_input(tty)) wait(tty) catch
            return if (count != 0) count else error.EINTR;

        const byte = tty.input_buffer.pop().?;
        c.* = byte;
        count += 1;

        if (is_end_of_line(tty, byte)) {
            // Not part of the line. A line holding only EOF gives a read of
            // zero, which is how a terminal reports end of input.
            if (byte == cc(tty, .VEOF)) count -= 1;
            break;
        }
    }
    return count;
}

/// Non-canonical reads, the four cases of POSIX 11.1.7.
///
///     MIN>0 TIME>0  block for the first byte, then TIME between bytes
///     MIN>0 TIME=0  block until MIN bytes
///     MIN=0 TIME>0  TIME bounds the whole read, which a byte also ends
///     MIN=0 TIME=0  whatever is there, at once, even nothing
///
/// MIN is capped by what the caller asked for.
fn read_raw(tty: *TtyStruct, s: []u8) TtyStruct.ReadError!usize {
    const vmin = @min(@as(usize, cc(tty, .VMIN)), s.len);
    const vtime = cc(tty, .VTIME);
    const inter_byte = vmin != 0 and vtime != 0;

    var count: usize = 0;
    var timer_id: ?u64 = null;
    defer if (timer_id) |id| timer.remove_by_id(id);

    tty.read_timed_out = false;
    // At zero MIN the timer bounds the read; above it, the gap between bytes.
    if (vmin == 0 and vtime != 0) timer_id = arm_timer(tty, vtime);

    while (true) {
        while (count < s.len) {
            const byte = tty.input_buffer.pop() orelse break;
            s[count] = byte;
            count += 1;

            if (inter_byte) {
                if (timer_id) |id| timer.remove_by_id(id);
                timer_id = arm_timer(tty, vtime);
            }
        }

        if (count == s.len) break;
        // Nothing to wait for: MIN and TIME both zero take what is there.
        if (vmin == 0 and vtime == 0) break;
        // MIN bytes have arrived, or with MIN at zero, the one byte that ends
        // a timed read.
        if (count >= vmin and (vmin != 0 or count != 0)) break;
        // The gap or the read timer ran out.
        if (tty.read_timed_out) break;

        wait(tty) catch return if (count != 0) count else error.EINTR;
    }
    return count;
}
