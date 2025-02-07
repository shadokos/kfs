const ft = @import("ft");

pub const PrivilegeLevel = enum(u2) {
    Supervisor = 0,
    User = 3,
};

const Cr0Flag = enum(u5) {
    ProtectedMode = 0,
    MathPresent = 1,
    Emulation = 2,
    TaskSwitched = 3,
    ExtensionType = 4,
    Paging = 31,
};

const Cr0 = packed struct(u32) {
    pe: bool = false,
    mp: bool = false,
    em: bool = false,
    ts: bool = false,
    et: bool = false,
    unused: u26,
    pg: bool = false,
};

pub const TableType = enum(u1) {
    GDT = 0,
    LDT = 1,
};

pub const Selector = packed struct(u16) {
    privilege: PrivilegeLevel = .Supervisor,
    table: TableType = .GDT,
    index: u13 = 0,
};

pub const EFlags = packed struct(u32) {
    carry: bool = false,
    reserved1: u1 = 1,
    parity: bool = false,
    reserved2: u1 = 0,
    auxiliary_carry: bool = false,
    reserved3: u1 = 0,
    zero: bool = false,
    sign: bool = false,
    trap: bool = false,
    interrupt_enable: bool = false,
    direction: bool = false,
    overflow: bool = false,
    iopl: PrivilegeLevel = .Supervisor,
    nested_task: bool = false,
    reserved4: u1 = 0,
    resume_flag: bool = false,
    virtual_8086: bool = false,
    reserved5: u14 = 0,
};

pub inline fn get_eflags() EFlags {
    return asm volatile (
        \\ pushfd
        \\ pop %eax
        : [_] "={eax}" (-> EFlags),
    );
}

pub inline fn get_cr0() Cr0 {
    return asm (
        \\ mov %cr0, %eax
        : [_] "={eax}" (-> Cr0),
    );
}

pub inline fn set_cr0(value: Cr0) void {
    asm volatile (
        \\ mov %eax, %cr0
        :
        : [_] "{eax}" (value),
    );
}

pub inline fn get_cr2() u32 {
    return asm (
        \\ mov %cr2, %eax
        : [_] "={eax}" (-> u32),
    );
}

pub inline fn get_cr3() u32 {
    return asm (
        \\ mov %cr3, %eax
        : [_] "={eax}" (-> u32),
    );
}

pub inline fn set_cr3(value: u32) void {
    asm volatile (
        \\ mov %eax, %cr3
        :
        : [_] "{eax}" (value),
    );
}

pub inline fn reload_cr3() void {
    asm volatile (
        \\ mov %cr3, %eax
        \\ mov %eax, %cr3
        :
        : [_] "{eax}" (42), // zig seems to optimize this asm call away when it take no input
    );
}

pub inline fn set_flag(flag: Cr0Flag) void {
    asm volatile (
        \\ mov %cr0, %eax
        \\ or %ebx, %eax
        \\ mov %eax, %cr0
        :
        : [_] "{ebx}" (@as(u32, 1) << @intFromEnum(flag)),
    );
}

pub inline fn unset_flag(flag: Cr0Flag) void {
    asm volatile (
        \\ mov %cr0, %eax
        \\ and %ebx, %eax
        \\ mov %eax, %cr0
        :
        : [_] "{ebx}" (~(@as(u32, 1) << @intFromEnum(flag))),
    );
}

pub inline fn get_esp() u32 {
    return asm (
        \\ mov %esp, %eax
        : [_] "={eax}" (-> u32),
    );
}

pub inline fn set_esp(value: u32) void {
    asm volatile (""
        :
        : [_] "{esp}" (value),
    );
}

pub const Ports = enum(u16) {
    vga_idx_reg = 0x03d4,
    vga_io_reg = 0x03d5,
    pic_master_command = 0x0020,
    pic_master_data = 0x0021,
    pic_slave_command = 0x00a0,
    pic_slave_data = 0x00a1,
    com_port_1 = 0x03f8,
    com_port_2 = 0x02f8,
};

inline fn _get_port(port: anytype) u16 {
    return switch (@typeInfo(@TypeOf(port))) {
        .@"enum", .enum_literal => @intFromEnum(@as(Ports, port)),
        .int, .comptime_int => @truncate(port),
        else => @compileError("Invalid port type"),
    };
}

pub inline fn inb(port: anytype) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (_get_port(port)),
    );
}

pub inline fn outb(port: anytype, data: u8) void {
    asm volatile ("outb %[data], %[port]"
        :
        : [data] "{al}" (data),
          [port] "{dx}" (_get_port(port)),
    );
}

pub inline fn inw(port: anytype) u16 {
    return asm volatile ("inw %[port], %[result]"
        : [result] "={ax}" (-> u16),
        : [port] "N{dx}" (_get_port(port)),
    );
}

pub inline fn outw(port: usize, data: u16) void {
    asm volatile ("outw %[data], %[port]"
        :
        : [data] "{ax}" (data),
          [port] "{dx}" (_get_port(port)),
    );
}

pub inline fn inl(port: anytype) u32 {
    return asm volatile ("inl %[port], %[result]"
        : [result] "={eax}" (-> u32),
        : [port] "N{dx}" (_get_port(port)),
    );
}

pub inline fn outl(port: anytype, data: u32) void {
    asm volatile ("outl %[data], %[port]"
        :
        : [data] "{eax}" (data),
          [port] "{dx}" (_get_port(port)),
    );
}

pub inline fn io_wait() void {
    outb(0x80, 0);
}

pub inline fn enable_interrupts() void {
    asm volatile ("sti");
}

pub inline fn disable_interrupts() void {
    asm volatile ("cli");
}

pub inline fn load_idt(idtr: *const @import("interrupts.zig").IDTR) void {
    asm volatile ("lidt (%%eax)"
        :
        : [idtr] "{eax}" (idtr),
    );
}

pub inline fn load_gdt(gdtr: *const @import("gdt.zig").GDTR) void {
    asm volatile ("lgdt (%%eax)"
        :
        : [idtr] "{eax}" (gdtr),
    );
}

pub inline fn load_tss(selector: Selector) void {
    asm volatile (
        \\ ltr %[selector]
        :
        : [selector] "{ax}" (selector),
    );
}

// todo: non comptime code segment
pub inline fn load_segments(comptime code: Selector, data: Selector, stack: Selector) void {
    comptime var code_selector_buf: [10]u8 = undefined;
    comptime var stream = ft.io.fixedBufferStream(code_selector_buf[0..]);
    comptime stream.writer().print("0b{b}", .{@as(u16, @bitCast(code))}) catch |e| @compileError(e);
    asm volatile ("jmp $" ++ stream.getWritten() ++ ", $.reload_CS\n" ++
            \\ .reload_CS:
            \\ movw %[data], %ax
            \\ movw %ax, %ds
            \\ movw %ax, %es
            \\ movw %ax, %fs
            \\ movw %ax, %gs
            \\ movw %[stack], %ax
            \\ movw %ax, %ss
        :
        : [code] "{bx}" (code),
          [data] "{cx}" (data),
          [stack] "{dx}" (stack),
    );
}

pub inline fn halt() void {
    asm volatile ("hlt");
}
