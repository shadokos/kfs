// Serial port TTY driver (16550 UART).
//
// Probes, activates, and manages COM1-COM4 as TTY devices.
// Each detected port gets a TtyStruct slot, a CharDevice entry,
// and an IRQ handler for interrupt-driven receive.
const std = @import("std");
const cpu = @import("../../cpu.zig");
const TtyStruct = @import("../../device/tty/tty_struct.zig");
const TtyDriver = @import("../../device/tty/tty_driver.zig");
const tty_mod = @import("../../device/tty/tty.zig");
const termios_mod = @import("../../device/tty/termios.zig");
const tty_cdev = @import("tty_cdev.zig");
const interrupts = @import("../../interrupts.zig");
const pic = @import("../../drivers/pic/pic.zig");

const log = std.log.scoped(.serial_tty);

const Self = @This();

pub const MAX_SERIAL_PORTS = 4;

/// Standard COM port I/O base addresses.
const com_ports = [MAX_SERIAL_PORTS]u16{ 0x3F8, 0x2F8, 0x3E8, 0x2E8 };
const com_names = [MAX_SERIAL_PORTS][]const u8{ "ttyS0", "ttyS1", "ttyS2", "ttyS3" };

/// UART base clock frequency (Hz).
const UART_BASE_CLOCK = 115200;

/// I/O port address for this UART.
port: u16,

/// Back-pointer to the owning TtyStruct.
tty: *TtyStruct = undefined,

/// Whether this serial TTY is active.
active: bool = false,

/// Check if the UART transmit holding register is empty.
fn is_transmit_empty(self: *const Self) bool {
    return cpu.inb(self.port + 5) & 0x20 == 0;
}

/// Write a single byte to the UART, blocking until the THR is ready.
fn uart_putc(self: *const Self, c: u8) void {
    while (self.is_transmit_empty()) cpu.halt();
    cpu.outb(self.port, c);
}

/// Check if the UART receive buffer has data.
fn uart_received(self: *const Self) bool {
    return cpu.inb(self.port + 5) & 1 != 0;
}

/// Configure baud rate, line params, FIFO, and run a loopback self-test.
fn activate(self: *Self) error{SerialPortFaulty}!void {
    const p = self.port;

    // Disable all interrupts during configuration
    cpu.outb(p + 1, 0x00);

    // Enable DLAB, set baud rate divisor = 1 (115200 baud)
    cpu.outb(p + 3, 0x80);
    cpu.outb(p + 0, 0x01);
    cpu.outb(p + 1, 0x00);

    // 8 data bits, no parity, 1 stop bit (8N1)
    cpu.outb(p + 3, 0x03);

    // Enable FIFO, clear TX/RX, 14-byte threshold
    cpu.outb(p + 2, 0xC7);

    // IRQs enabled, RTS/DSR set
    cpu.outb(p + 4, 0x0B);

    // Loopback mode for self-test
    cpu.outb(p + 4, 0x1E);

    // Flush receive buffer
    while (self.uart_received()) _ = cpu.inb(p);

    // Send test byte and verify
    cpu.outb(p, 0xAE);
    if (cpu.inb(p) != 0xAE)
        return error.SerialPortFaulty;

    // Normal operation mode, enable receive data interrupt
    cpu.outb(p + 4, 0x0F);
    cpu.outb(p + 1, 0x01);
}

/// Wire this serial port to a TtyStruct (raw mode defaults).
pub fn serial_init(self: *Self, tty_s: *TtyStruct) void {
    self.tty = tty_s;
    tty_s.driver = &serial_driver;
    tty_s.driver_data = @ptrCast(self);

    // Serial TTYs default to raw mode (no canonical processing).
    tty_s.config.c_lflag.ICANON = false;
    tty_s.config.c_lflag.ECHO = true;
    tty_s.config.c_lflag.ECHOCTL = true;
    tty_s.config.c_lflag.ECHONL = false;
    // Enable basic output processing (ONLCR for serial terminals).
    tty_s.config.c_oflag.OPOST = true;
    tty_s.config.c_oflag.ONLCR = true;
}

/// Probe for a UART at the given I/O address (scratch register test).
fn probe_port(port_addr: u16) bool {
    const original = cpu.inb(port_addr + 7);
    cpu.outb(port_addr + 7, 0xA5);
    const readback = cpu.inb(port_addr + 7);
    cpu.outb(port_addr + 7, original);
    return readback == 0xA5;
}

// TtyDriver callbacks

fn serial_write(tty_s: *TtyStruct, data: []const u8) usize {
    const self = get_serial_tty(tty_s);
    for (data) |c| self.uart_putc(c);
    return data.len;
}

fn serial_put_char(tty_s: *TtyStruct, c: u8) void {
    get_serial_tty(tty_s).uart_putc(c);
}

fn serial_flush(_: *TtyStruct) void {}

/// Poll the UART for incoming data and feed it into the TTY input buffer.
fn serial_receive(tty_s: *TtyStruct) void {
    const self = get_serial_tty(tty_s);
    if (self.uart_received()) {
        var buf = [1]u8{cpu.inb(self.port)};
        tty_s.input(&buf);
    }
}

/// Reprogram UART registers when termios settings change.
fn serial_set_termios(tty_s: *TtyStruct, _: termios_mod.termios) void {
    const self = get_serial_tty(tty_s);
    const cfg = &tty_s.config;

    // Build Line Control Register: bits, stop, parity
    var lcr: u8 = @intFromEnum(cfg.c_cflag.CSIZE);
    if (cfg.c_cflag.CSTOPB) lcr |= 0x04;
    if (cfg.c_cflag.PARENB) {
        lcr |= 0x08;
        if (!cfg.c_cflag.PARODD) lcr |= 0x10;
    }

    // Reprogram divisor latch if baud rate is valid
    const baud = termios_mod.cfgetospeed(cfg);
    const baud_fp = termios_mod.baud_to_rate_fp(baud);
    if (baud_fp > 0) {
        const divisor: u16 = @intCast((UART_BASE_CLOCK * 10) / baud_fp);
        cpu.outb(self.port + 3, lcr | 0x80); // DLAB on
        cpu.outb(self.port + 0, @truncate(divisor));
        cpu.outb(self.port + 1, @truncate(divisor >> 8));
    }

    cpu.outb(self.port + 3, lcr); // DLAB off

    log.info("UART 0x{x}: {d} baud, {s}{s}{s}", .{
        self.port,
        termios_mod.baud_to_rate(baud),
        @as([]const u8, switch (cfg.c_cflag.CSIZE) {
            .CS5 => "5",
            .CS6 => "6",
            .CS7 => "7",
            .CS8 => "8",
        }),
        @as([]const u8, if (cfg.c_cflag.PARENB)
            (if (cfg.c_cflag.PARODD) "O" else "E")
        else
            "N"),
        @as([]const u8, if (cfg.c_cflag.CSTOPB) "2" else "1"),
    });
}

fn get_serial_tty(tty_s: *TtyStruct) *Self {
    return @ptrCast(@alignCast(tty_s.driver_data));
}

pub const serial_driver = TtyDriver{
    .write = &serial_write,
    .put_char = &serial_put_char,
    .flush = &serial_flush,
    .receive = &serial_receive,
    .set_termios = &serial_set_termios,
};

// Global state and initialization

/// Static serial TTY instances.
pub var ports: [MAX_SERIAL_PORTS]Self = undefined;

/// Number of detected and active serial ports.
pub var detected_count: usize = 0;

/// IRQ assignments for COM1 and COM2.
const com_irqs = [2]pic.IRQ{ .COM1, .COM2 };

fn com1_irq_handler(_: interrupts.InterruptFrame) void {
    drain_uart(0);
    pic.ack(.COM1);
}

fn com2_irq_handler(_: interrupts.InterruptFrame) void {
    drain_uart(1);
    pic.ack(.COM2);
}

/// Drain the UART FIFO into the TTY input buffer (IRQ context).
fn drain_uart(port_index: usize) void {
    const port = &ports[port_index];
    if (!port.active) return;
    while (port.uart_received()) {
        var buf = [1]u8{cpu.inb(port.port)};
        port.tty.input(&buf);
    }
}

/// Probe all COM ports, activate detected ones, wire them as TTYs,
/// register as CharDevices, and install IRQ handlers.
pub fn init() void {
    for (0..MAX_SERIAL_PORTS) |i| {
        if (!probe_port(com_ports[i])) {
            log.debug("{s}: not detected", .{com_names[i]});
            continue;
        }

        log.info("{s}: detected at 0x{x}", .{ com_names[i], com_ports[i] });

        ports[detected_count] = Self{ .port = com_ports[i] };

        ports[detected_count].activate() catch |err| {
            log.err("{s}: activation failed: {s}", .{ com_names[i], @errorName(err) });
            continue;
        };

        // Wire to a dedicated TtyStruct slot after the console range.
        const tty_idx = tty_mod.num_consoles + detected_count;
        if (tty_idx >= tty_mod.total_ttys) {
            log.err("{s}: no free TTY slot", .{com_names[i]});
            continue;
        }

        ports[detected_count].serial_init(&tty_mod.tty_array[tty_idx]);
        ports[detected_count].active = true;

        _ = tty_cdev.register_serial(com_names[i]) catch |err| {
            log.err("{s}: chardev registration failed: {s}", .{ com_names[i], @errorName(err) });
        };

        // Install IRQ handler for COM1 (IRQ4) and COM2 (IRQ3).
        if (i < 2) {
            const irq = com_irqs[i];
            const handler = if (i == 0)
                interrupts.Handler.create(&com1_irq_handler, false)
            else
                interrupts.Handler.create(&com2_irq_handler, false);
            interrupts.set_intr_gate(irq, handler);
            pic.enable_irq(irq);
        }

        detected_count += 1;
        log.info("{s}: initialized (tty slot {d})", .{ com_names[i], tty_idx });
    }

    if (detected_count == 0) {
        log.info("no serial ports detected", .{});
    } else {
        log.info("{d} serial port(s) initialized", .{detected_count});
    }
}
