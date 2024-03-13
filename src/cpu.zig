const ft = @import("../ft/ft.zig");

const Cr0Flag = enum(u5) { ProtectedMode = 0, MathPresent = 1, Emulation = 2, TaskSwitched = 3, ExtensionType = 4, Paging = 31 };

const Cr0 = packed struct(u32) {
    pe: bool = false,
    mp: bool = false,
    em: bool = false,
    ts: bool = false,
    et: bool = false,
    unused: u26,
    pg: bool = false,
};

pub inline fn get_cr0() Cr0 {
    return asm (
        \\ mov %cr0, %eax
        : [_] "={eax}" (Cr0),
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
        : [_] "={eax}" (Cr0),
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

pub const Ports = enum(u16) { vga_idx_reg = 0x03d4, vga_io_reg = 0x03d5 };

fn _get_port(port: anytype) u16 {
    return switch (@typeInfo(@TypeOf(port))) {
        .EnumLiteral => @intFromEnum(@as(Ports, port)),
        .Int, .ComptimeInt => @truncate(port),
        else => @compileError("Invalid port type"),
    };
}

pub fn inb(port: anytype) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (_get_port(port)),
    );
}

pub fn outb(port: anytype, data: u8) void {
    asm volatile ("outb %[data], %[port]"
        :
        : [data] "{al}" (data),
          [port] "{dx}" (_get_port(port)),
    );
}

pub fn inw(port: anytype) u16 {
    return asm volatile ("inw %[port], %[result]"
        : [result] "={ax}" (-> u16),
        : [port] "N{dx}" (_get_port(port)),
    );
}

pub fn outw(port: usize, data: u16) void {
    asm volatile ("outw %[data], %[port]"
        :
        : [data] "{ax}" (data),
          [port] "{dx}" (_get_port(port)),
    );
}

pub fn inl(port: anytype) u32 {
    return asm volatile ("inl %[port], %[result]"
        : [result] "={eax}" (-> u32),
        : [port] "N{dx}" (_get_port(port)),
    );
}

pub fn outl(port: anytype, data: u32) void {
    asm volatile ("outl %[data], %[port]"
        :
        : [data] "{eax}" (data),
          [port] "{dx}" (_get_port(port)),
    );
}
