const cpu = @import("../../cpu.zig");

const ICW1_ICW4 = 0x01; // ICW4 needed
const ICW1_SINGLE = 0x02; // Single (cascade) mode
const ICW1_INTERVAL4 = 0x04; // Call address interval 4 (8)
const ICW1_LEVEL = 0x08; // Level triggered (edge) mode
const ICW1_INIT = 0x10; // Initialization

const ICW4_8086 = 0x01; // 8086/88 (MCS-80/85) mode
const ICW4_AUTO = 0x02; // Auto (normal) EOI
const ICW4_BUF_SLAVE = 0x08; // Buffered mode/slave
const ICW4_BUF_MASTER = 0x0c; // Buffered mode/master
const ICW4_SFNM = 0x10; // Special fully nested (not)

pub const IRQS = enum {
    Timer,
    Keyboard,
    Slave,
    COM2,
    COM1,
    LPT2,
    FloppyDisk,
    LPT1,
    CMOSClock,
    ACPI,
    NetworkInterface,
    USBPort,
    PS2Mouse,
    Coprocessor,
    PrimaryATAHardDisk,
    SecondaryATAHardDisk,
};

fn get_irq_port_id(irq: IRQS) struct { id: u8, port: cpu.Ports } {
    var id: u8 = @intFromEnum(irq);
    var port = cpu.Ports.pic_master_data;

    if (id >= 8) {
        port = cpu.Ports.pic_slave_data;
        id -= 8;
    }
    return .{ .id = id, .port = port };
}

pub fn enable_irq(irq: IRQS) void {
    const port_id = get_irq_port_id(irq);
    const mask = cpu.inb(port_id.port);
    cpu.outb(port_id.port, mask & ~(@as(u8, 1) << @truncate(port_id.id)));
}

pub fn disable_irq(irq: IRQS) void {
    const port_id = get_irq_port_id(irq);
    const mask = cpu.inb(port_id.port);
    cpu.outb(port_id.port, mask | (@as(u8, 1) << @truncate(port_id.id)));
}

pub fn remap(offset1: u8, offset2: u8) void {
    cpu.outb(.pic_master_command, ICW1_INIT | ICW1_ICW4);
    cpu.io_wait();
    cpu.outb(.pic_slave_command, ICW1_INIT | ICW1_ICW4);
    cpu.io_wait();

    cpu.outb(.pic_master_data, offset1);
    cpu.io_wait();
    cpu.outb(.pic_slave_data, offset2);
    cpu.io_wait();

    cpu.outb(.pic_master_data, 0b0000_0100);
    cpu.io_wait();
    cpu.outb(.pic_slave_data, 2);
    cpu.io_wait();

    cpu.outb(.pic_master_data, ICW4_8086);
    cpu.io_wait();
    cpu.outb(.pic_slave_data, ICW4_8086);
    cpu.io_wait();

    cpu.outb(.pic_master_data, 0b1111_1111);
    cpu.outb(.pic_slave_data, 0b1111_1111);
}

pub inline fn ack() void {
    cpu.outb(0x20, 0x20);
}
