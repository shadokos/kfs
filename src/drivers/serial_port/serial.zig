const ft = @import("../../ft/ft.zig");
pub const cpu = @import("../../cpu.zig");
const logger = @import("../../ft/ft.zig").log.scoped(.serial);

const Self = @This();
pub const Reader = ft.io.Reader(*Self, anyerror, read);
pub const Writer = ft.io.Writer(*Self, anyerror, write);

port: cpu.Ports = undefined,

pub fn init(comptime port: @TypeOf(.enum_literal)) Self {
    return Self{ .port = port };
}

pub fn activate(self: *Self) error{SerialPortFaulty}!void {
    const port_nbr = @intFromEnum(self.port);
    const port_name = @tagName(self.port);

    logger.debug("{s}: Disable all interrupts", .{port_name});
    cpu.outb(port_nbr + 1, 0x00);

    logger.debug("{s}: Enable DLAB (set baud rate divisor)", .{port_name});
    cpu.outb(port_nbr + 3, 0x80);
    cpu.outb(port_nbr + 0, 0x01);
    cpu.outb(port_nbr + 1, 0x00);

    logger.debug("{s}: 8 bits, no parity, one stop bit", .{port_name});
    cpu.outb(port_nbr + 3, 0x03);

    logger.debug("{s}: Enable FIFO, clear them, with 14-byte threshold", .{port_name});
    cpu.outb(port_nbr + 2, 0xC7);

    logger.debug("{s}: IRQs enabled, RTS/DSR set", .{port_name});
    cpu.outb(port_nbr + 4, 0x0B);

    logger.debug("{s}: Set in loopback mode, test the serial chip", .{port_name});
    cpu.outb(port_nbr + 4, 0x1E);

    logger.debug("{s}: Flush the buffer", .{port_name});
    while (self.serial_received()) _ = cpu.inb(port_nbr);

    logger.debug("{s}: Test serial chip (send byte 0xAE and check if serial returns same byte)", .{port_name});
    cpu.outb(port_nbr + 0, 0xAE);

    if (cpu.inb(port_nbr + 0) != 0xAE) {
        logger.err("Serial port " ++ "{s}is faulty", .{port_name});
        return error.SerialPortFaulty;
    }

    logger.debug("{s}: setting up normal operation mode", .{port_name});
    cpu.outb(port_nbr + 4, 0x0f);
    cpu.outb(port_nbr + 1, 0x01);

    logger.info("{s} initialized", .{port_name});
}

pub fn is_transmit_empty(self: *Self) bool {
    return (cpu.inb(@intFromEnum(self.port) + 5) & 0x20 == 0);
}

pub fn putstr_serial(comptime port: @TypeOf(.enum_literal), str: []const u8) void {
    for (str) |c| write_serial(port, c);
    write_serial(port, '\n');
}

pub fn write_serial(self: *Self, a: u8) void {
    while (self.is_transmit_empty()) cpu.halt();
    cpu.outb(@intFromEnum(self.port), a);
}

pub fn serial_received(self: *Self) bool {
    return (cpu.inb(@intFromEnum(self.port) + 5) & 1 != 0);
}

pub fn read(self: *Self, buff: []u8) error{NoData}!usize {
    const port_nbr = @intFromEnum(self.port);

    while (!self.serial_received()) cpu.halt();
    buff[0] = cpu.inb(port_nbr);
    return 1;
}

pub fn write(self: *Self, buff: []const u8) error{}!usize {
    var len: usize = 0;
    for (buff) |c| {
        self.write_serial(c);
        len += 1;
    }
    return len;
}

pub fn get_writer(self: *Self) Self.Writer {
    return Self.Writer{ .context = self };
}

pub fn get_reader(self: *Self) Self.Reader {
    return Self.Reader{ .context = self };
}
