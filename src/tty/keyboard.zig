const ft = @import("../ft/ft.zig");
const tty = @import("tty.zig");
const ps2 = @import("../drivers/ps2/ps2.zig");
const pic = @import("../drivers/pic/pic.zig");
const keymap = @import("keyboard/keymap.zig");
const scanmap = @import("keyboard/scanmap.zig");
const scanmap_normal = scanmap.scanmap_normal;
const scanmap_special = scanmap.scanmap_special;

const SCANCODE_MASK_RELEASED = 0x80;
const SCANCODE_MASK_INDEX = 0x7F;
const KEYBOARD_INPUT_SIZE = 32;

pub const KeyState = struct {
    shift_left: bool = false,
    shift_right: bool = false,
    shift: bool = false,
    ctrl_left: bool = false,
    ctrl_right: bool = false,
    ctrl: bool = false,
    alt_left: bool = false,
    alt_right: bool = false,
    alt: bool = false,
    num_down: bool = false,
    caps_down: bool = false,
    alt_lock: bool = false,
};

pub const KeyLocks = packed struct {
    caps_lock: bool = false,
    num_lock: bool = false,
};

const ScanMode = enum(u2) {
    Normal = 0,
    Extended = 1,
    Pause = 2,
};

var inbuf: [KEYBOARD_INPUT_SIZE]u16 = [_]u16{0} ** KEYBOARD_INPUT_SIZE;
var intail: u8 = 0;
var inhead: u8 = 0;
var incount: u8 = 0;

pub var keyState: KeyState = .{};
pub var locks: KeyLocks = .{};
var scan_mode: ScanMode = .Normal;

pub fn send_to_tty(data: []const u8) void {
    const current: *tty.Tty = &tty.tty_array[tty.current_tty];

    current.input(data);
}

fn send_to_buffer(scan_code: u16) void {
    if (incount < KEYBOARD_INPUT_SIZE) {
        inbuf[inhead] = scan_code;
        inhead = (inhead + 1) % KEYBOARD_INPUT_SIZE;
        incount += 1;
    }
}

fn make_break(scancode: u16) ?u16 {
    var c = scancode & 0x7FFF;
    var make: bool = !(scancode & 0x8000 != 0);

    c = keymap.map_key(c);
    switch (c) {
        keymap.RCTRL => {
            keyState.ctrl_right = make;
            keyState.ctrl = make;
        },
        keymap.LCTRL => {
            keyState.ctrl_left = make;
            keyState.ctrl = make;
        },
        keymap.RSHIFT => {
            keyState.shift_right = make;
            keyState.shift = make;
        },
        keymap.LSHIFT => {
            keyState.shift_left = make;
            keyState.shift = make;
        },
        keymap.RALT => {
            keyState.alt_right = make;
            keyState.alt = make;
        },
        keymap.LALT => {
            keyState.alt_left = make;
            keyState.alt = make;
        },
        keymap.CALOCK => {
            if (!keyState.caps_down and make)
                locks.caps_lock = !locks.caps_lock;
            keyState.caps_down = make;
        },
        keymap.NLOCK => {
            if (!keyState.num_down and make)
                locks.num_lock = !locks.num_lock;
            keyState.num_down = make;
        },
        keymap.PGUP, keymap.PGDN => if (make) {
            if (!@import("build_options").posix) {
                if (keyState.shift) {
                    tty.get_tty().scroll(if (c == keymap.PGUP) tty.height else -tty.height);
                } else {
                    tty.get_tty().scroll(if (c == keymap.PGUP) 1 else -1);
                }
            } else return c;
        },
        keymap.AF1...keymap.AF10 => if (keyState.ctrl and !make) {
            tty.set_tty(@intCast(c - keymap.AF1)) catch unreachable;
        },
        else => if (make and c != 0) {
            if (!@import("build_options").posix) {
                tty.get_tty().reset_scroll();
            }
            return c;
        },
    }
    return null;
}

pub fn kb_read() void {
    while (incount != 0) {
        const scancode: u16 = inbuf[intail];

        intail = (intail + 1) % KEYBOARD_INPUT_SIZE;
        incount -|= 1;

        const c = make_break(scancode) orelse continue;

        switch (c) {
            0...0xff => send_to_tty(&[1]u8{@intCast(c)}),
            keymap.HOME...keymap.INSRT => send_to_tty(keymap.escape_map[c - keymap.HOME]),
            else => {},
        }
    }
}

pub fn handler() callconv(.Interrupt) void {
    const scan_code: u8 = ps2.get_data();
    const index: u8 = scan_code & SCANCODE_MASK_INDEX;
    const released: u16 = scan_code & SCANCODE_MASK_RELEASED;

    scan_mode = switch (scan_mode) {
        .Extended => b: {
            if (index < scanmap_special.len and scanmap_special[index] != .NONE)
                send_to_buffer(@intFromEnum(scanmap_special[index]) | (released << 8));
            break :b .Normal;
        },
        .Pause => .Normal, // Skip the byte, it's a pause and i personnaly don't care yet
        .Normal => switch (scan_code) {
            0xE0 => .Extended,
            0xE1 => .Pause,
            else => b: {
                if (index < scanmap_normal.len and scanmap_normal[index] != .NONE)
                    send_to_buffer(@intFromEnum(scanmap_normal[index]) | (released << 8));
                break :b .Normal;
            },
        },
    };
    pic.ack();
}

fn is_key_available() bool {
    return ps2.get_status().output_buffer == 1;
}

pub fn init() void {
    const interrupts = @import("../interrupts.zig");
    ps2.set_first_port_interrupts(true);
    interrupts.set_intr_gate(pic.IRQS.Keyboard, interrupts.Handler{ .noerr = &handler });
    pic.enable_irq(pic.IRQS.Keyboard);
}
