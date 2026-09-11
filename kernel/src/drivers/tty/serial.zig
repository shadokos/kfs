// A 16550 UART driving a terminal. What a line needs and a screen does not, an
// output queue and a way to wait for it, is all here.

const std = @import("std");

const cpu = @import("../../cpu.zig");
const pic = @import("../pic/pic.zig");
const interrupts = @import("../../interrupts.zig");

const wait_queue = @import("../../task/wait_queue.zig");
const scheduler = @import("../../task/scheduler.zig");

const tty = @import("../../tty/tty.zig");
const TtyStruct = @import("../../tty/TtyStruct.zig");
const TtyDriver = @import("../../tty/TtyDriver.zig");
const termios = @import("../../tty/termios.zig");

const log = std.log.scoped(.serial);

/// The UART's own clock, from which every baud rate is divided down.
const base_clock: u32 = 115200;

/// Register offsets from the port base.
const data = 0;
const interrupt_enable = 1;
const fifo_control = 2;
const line_control = 3;
const modem_control = 4;
const line_status = 5;

/// Output waiting for the transmitter. A console needs none: it has written by
/// the time it is asked.
const Ring = struct {
    buffer: [512]u8 = undefined,
    head: u9 = 0,
    tail: u9 = 0,

    fn is_empty(self: *const Ring) bool {
        return self.head == self.tail;
    }

    fn is_full(self: *const Ring) bool {
        return self.head +% 1 == self.tail;
    }

    fn push(self: *Ring, c: u8) bool {
        if (self.is_full()) return false;
        self.buffer[self.head] = c;
        self.head +%= 1;
        return true;
    }

    fn pop(self: *Ring) ?u8 {
        if (self.is_empty()) return null;
        const c = self.buffer[self.tail];
        self.tail +%= 1;
        return c;
    }

    fn clear(self: *Ring) void {
        self.tail = self.head;
    }
};

const Self = @This();

port: u16,
irq: pic.IRQ,
terminal: *TtyStruct = undefined,
tx: Ring = .{},

/// Whoever is waiting for the line to fall silent, for tcdrain.
drain_queue: wait_queue.WaitQueue(.{ .predicate = sent_everything }) = .{},

/// Whether the transmitter is idle and waiting to be handed a byte.
fn can_transmit(self: *const Self) bool {
    return cpu.inb(self.port + line_status) & 0x20 != 0;
}

fn has_received(self: *const Self) bool {
    return cpu.inb(self.port + line_status) & 0x01 != 0;
}

/// Holding and shift register both empty: the last bit has left the wire.
fn is_idle(self: *const Self) bool {
    return cpu.inb(self.port + line_status) & 0x40 != 0;
}

fn sent_everything(_: *void, waiter: ?*void) bool {
    const self: *Self = @ptrCast(@alignCast(waiter.?));
    return self.tx.is_empty();
}

/// Ask the transmitter to say when it has room, or stop asking. It has room
/// whenever there is nothing to send, so leaving this on never stops firing.
fn want_room(self: *Self, wanted: bool) void {
    const current = cpu.inb(self.port + interrupt_enable);
    const next = if (wanted) current | 0x02 else current & ~@as(u8, 0x02);
    if (next != current) cpu.outb(self.port + interrupt_enable, next);
}

/// Hand the transmitter as much as it will take, and arrange to be told when
/// it wants more.
fn kick(self: *Self) void {
    while (self.can_transmit()) {
        const c = self.tx.pop() orelse break;
        cpu.outb(self.port + data, c);
    }

    self.want_room(!self.tx.is_empty());
    if (self.tx.is_empty()) self.drain_queue.try_unblock();
}

// Driver

fn write(terminal: *TtyStruct, bytes: []const u8) usize {
    const self = of(terminal);

    for (bytes) |c| {
        // A full queue means the wire is slower than the writer, so wait for
        // room rather than lose what there was to say. Unlike input, which has
        // nowhere to wait and drops at MAX_INPUT.
        while (!self.tx.push(c)) self.kick();
    }
    self.kick();
    return bytes.len;
}

fn flush(terminal: *TtyStruct) void {
    of(terminal).kick();
}

/// Wait for everything to have left, for tcdrain. The byte in the shift
/// register has no interrupt of its own, hence the spin at the end.
fn drain(terminal: *TtyStruct) void {
    const self = of(terminal);

    while (!self.tx.is_empty())
        self.drain_queue.block_no_int(scheduler.get_current_task(), @ptrCast(self));

    while (!self.is_idle()) cpu.halt();
}

/// Push the queue out by hand, for a caller that cannot wait. A panic runs with
/// interrupts off, so the transmit interrupt is never going to come.
pub fn flush_sync(terminal: *TtyStruct) void {
    const self = of(terminal);

    while (self.tx.pop()) |c| {
        while (!self.can_transmit()) {}
        cpu.outb(self.port + data, c);
    }
    while (!self.is_idle()) {}
}

fn flush_output(terminal: *TtyStruct) void {
    const self = of(terminal);
    self.tx.clear();
    self.want_room(false);
    self.drain_queue.try_unblock();
}

/// Take in what arrived. Called from the input task, never from the interrupt.
fn receive(terminal: *TtyStruct) void {
    const self = of(terminal);
    while (self.has_received()) {
        const byte = [1]u8{cpu.inb(self.port + data)};
        terminal.input(&byte);
    }
}

/// Reprogram the line when termios changes: speed, character size, parity and
/// stop bits.
fn set_termios(terminal: *TtyStruct, _: termios.termios) void {
    const self = of(terminal);
    const config = &terminal.config;

    var lcr: u8 = 0x03; // 8 bits, the only size the kernel's termios carries
    if (config.c_cflag.CSTOPB) lcr |= 0x04;
    if (config.c_cflag.PARENB) {
        lcr |= 0x08;
        if (!config.c_cflag.PARODD) lcr |= 0x10;
    }

    cpu.outb(self.port + line_control, lcr);
}

/// Drop DTR and RTS, which is how a UART hangs up.
fn hangup(terminal: *TtyStruct) void {
    cpu.outb(of(terminal).port + modem_control, 0x00);
}

pub const driver = TtyDriver{
    .write = &write,
    .flush = &flush,
    .drain = &drain,
    .flush_output = &flush_output,
    .receive = &receive,
    .set_termios = &set_termios,
    .hangup = &hangup,
};

fn of(terminal: *TtyStruct) *Self {
    return @ptrCast(@alignCast(terminal.driver_data.?));
}

// Bring-up

const com_ports = [_]u16{ 0x3F8, 0x2F8, 0x3E8, 0x2E8 };
const com_names = [_][]const u8{ "ttyS0", "ttyS1", "ttyS2", "ttyS3" };

/// COM1 and COM3 share one interrupt line, COM2 and COM4 the other.
const com_irqs = [_]pic.IRQ{ .COM1, .COM2, .COM1, .COM2 };

pub var ports: [com_ports.len]Self = undefined;
pub var detected: usize = 0;

/// The terminal on the first line found, for a caller with no descriptor to
/// reach it by. Null until init has run.
pub fn first_line() ?*TtyStruct {
    return if (detected > 0) ports[0].terminal else null;
}

/// A scratch register that keeps what is written to it is a UART.
fn probe(port: u16) bool {
    const previous = cpu.inb(port + 7);
    cpu.outb(port + 7, 0xA5);
    const readback = cpu.inb(port + 7);
    cpu.outb(port + 7, previous);
    return readback == 0xA5;
}

/// Configure the line and check the chip answers, in loopback.
fn activate(self: *Self) error{Faulty}!void {
    const p = self.port;

    cpu.outb(p + interrupt_enable, 0x00);
    cpu.outb(p + line_control, 0x80); // divisor latch
    cpu.outb(p + data, 0x01); // 115200 baud
    cpu.outb(p + interrupt_enable, 0x00);
    cpu.outb(p + line_control, 0x03); // 8N1
    cpu.outb(p + fifo_control, 0xC7);
    cpu.outb(p + modem_control, 0x1E); // loopback

    while (self.has_received()) _ = cpu.inb(p + data);
    cpu.outb(p + data, 0xAE);
    if (cpu.inb(p + data) != 0xAE) return error.Faulty;

    cpu.outb(p + modem_control, 0x0F);
    cpu.outb(p + interrupt_enable, 0x01); // received data available
    return;
}

/// Take what arrived, give the transmitter what it has room for. Reading the
/// line is left to the input task.
fn service(self: *Self) void {
    if (self.has_received()) tty.notify(self.terminal);
    self.kick();
}

/// A shared line says only which pair the interrupt came from, so both ports
/// on it are asked.
fn service_irq(irq: pic.IRQ) void {
    for (ports[0..detected]) |*p| if (p.irq == irq) p.service();
}

fn uses_irq(irq: pic.IRQ) bool {
    for (ports[0..detected]) |*p| if (p.irq == irq) return true;
    return false;
}

fn com1_handler(_: interrupts.InterruptFrame) void {
    pic.ack(.COM1);
    service_irq(.COM1);
}

fn com2_handler(_: interrupts.InterruptFrame) void {
    pic.ack(.COM2);
    service_irq(.COM2);
}

pub fn init() void {
    for (com_ports, com_names, com_irqs) |port, name, irq| {
        if (!probe(port)) continue;

        const line = tty.claim_line(detected) orelse {
            log.warn("{s}: no terminal left to attach it to", .{name});
            break;
        };

        ports[detected] = .{ .port = port, .irq = irq };
        ports[detected].activate() catch {
            log.warn("{s}: faulty, skipped", .{name});
            continue;
        };

        ports[detected].terminal = line;
        line.driver = &driver;
        line.driver_data = @ptrCast(&ports[detected]);

        // A line has a carrier to lose; CLOCAL would make every hangup a
        // no-op, POSIX 11.1.10.
        var config = line.config;
        config.c_cflag.CLOCAL = false;
        line.set_termios(config);

        detected += 1;

        @import("tty_cdev.zig").register_line(name, line.index) catch |err|
            log.err("{s}: {s}", .{ name, @errorName(err) });

        log.info("{s} at 0x{x}, terminal {d}", .{ name, port, line.index });
    }

    if (uses_irq(.COM1)) {
        interrupts.set_intr_gate(pic.IRQ.COM1, interrupts.Handler.create(&com1_handler, false));
        pic.enable_irq(pic.IRQ.COM1);
    }
    if (uses_irq(.COM2)) {
        interrupts.set_intr_gate(pic.IRQ.COM2, interrupts.Handler.create(&com2_handler, false));
        pic.enable_irq(pic.IRQ.COM2);
    }
}
