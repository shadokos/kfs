const cpu = @import("../../cpu.zig");

const logger = @import("std").log.scoped(.driver_pic);

pub const offset_master: u8 = 0x20;
pub const offset_slave: u8 = 0x28;

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

pub const IRQ = enum {
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

var spurious_master: u32 = 0;
var spurious_slave: u32 = 0;

fn get_irq_port_id(irq: IRQ) struct { id: u8, port: cpu.Ports } {
    var id: u8 = @intFromEnum(irq);
    var port = cpu.Ports.pic_master_data;

    if (id >= 8) {
        port = cpu.Ports.pic_slave_data;
        id -= 8;
    }
    return .{ .id = id, .port = port };
}

pub fn enable_slave() void {
    enable_irq(.Slave);
}

pub fn try_disable_slave() void {
    if (cpu.inb(cpu.Ports.pic_slave_data) == 0xff) {
        disable_irq(.Slave);
    }
}

pub fn disable_slave() void {
    disable_irq(.Slave);
}

pub fn enable_irq(irq: IRQ) void {
    const port_id = get_irq_port_id(irq);
    const mask = cpu.inb(port_id.port);

    cpu.outb(port_id.port, mask & ~(@as(u8, 1) << @truncate(port_id.id)));
    if (@intFromEnum(irq) >= 8)
        enable_slave();
}

pub fn enable_all_irqs() void {
    cpu.outb(cpu.Ports.pic_master_data, 0x00);
    cpu.outb(cpu.Ports.pic_slave_data, 0x00);
}

pub fn disable_irq(irq: IRQ) void {
    const port_id = get_irq_port_id(irq);
    const mask = cpu.inb(port_id.port);

    cpu.outb(port_id.port, mask | (@as(u8, 1) << @truncate(port_id.id)));
    if (@intFromEnum(irq) >= 8)
        try_disable_slave();
}

pub fn disable_all_irqs() void {
    cpu.outb(cpu.Ports.pic_master_data, 0xff);
    cpu.outb(cpu.Ports.pic_slave_data, 0xff);
}

pub fn remap(offset1: u8, offset2: u8) void {
    logger.debug("Remapping PIC with offsets {} and {}", .{ offset1, offset2 });
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

pub inline fn ack(irq: IRQ) void {
    cpu.outb(.pic_master_command, 0x20);
    if (@intFromEnum(irq) >= 8)
        cpu.outb(.pic_slave_command, 0x20);
}

// Check if the interrupt is spurious and acknowledge it accordingly
// Returns true if the interrupt was spurious
pub fn ack_spurious_interrupt(id: u8) bool {
    const master_isr = cpu.inb(.pic_master_command);
    const slave_isr = cpu.inb(.pic_slave_command);

    // If the interrupt is spurious, the ISR bit will be 0
    if (id == 7 and master_isr & 0b1000_0000 == 0) {
        // Spurious interrupt for the master PIC
        // nothing to do as it's not a real interrupt
        spurious_master += 1;
        return true;
    } else if (id == 15 and slave_isr & 0b1000_0000 == 0) {
        // Spurious interrupt for the slave PIC,
        // we need to acknowledge the master PIC as the mster don't know that the slave interrupt was spurious.
        // Note: here, .Slave is the IRQ for the slave PIC on the master PIC, not the slave PIC itself.
        spurious_slave += 1;
        ack(.Slave);
        return true;
    }
    return false;
}

pub fn get_spurious_master() u32 {
    return spurious_master;
}

pub fn get_spurious_slave() u32 {
    return spurious_slave;
}

pub fn get_irq_from_interrupt_id(comptime id: u8) IRQ {
    if (id >= offset_master and id <= offset_master + 8) {
        return @enumFromInt(id - offset_master);
    } else if (id >= offset_slave and id <= offset_slave + 8) {
        return @enumFromInt(id - offset_slave);
    } else {
        @compileLog(id);
        @compileError("Invalid interrupt ID for PIC");
    }
}

pub fn get_interrupt_id_from_irq(irq: IRQ) !u8 {
    const id = @intFromEnum(irq);
    return if (id < 8) id + offset_master else if (id < 16) id + offset_slave - 8 else error.InvalidIRQ;
}

pub fn init() void {
    logger.debug("Initializing PIC", .{});
    remap(offset_master, offset_slave);
    logger.info("PIC initialized", .{});
}
