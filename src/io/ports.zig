pub const Ports = enum(u16) { vga_idx_reg = 0x03d4, vga_io_reg = 0x03d5 };

fn _inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

fn _outb(port: u16, data: u8) void {
    asm volatile ("outb %[data], %[port]"
        :
        : [data] "{al}" (data),
          [port] "{dx}" (port),
    );
}

fn _inw(port: u16) u16 {
    return asm volatile ("inw %[port], %[result]"
        : [result] "={ax}" (-> u16),
        : [port] "N{dx}" (port),
    );
}

fn _outw(port: u16, data: u16) void {
    asm volatile ("outw %[data], %[port]"
        :
        : [data] "{ax}" (data),
          [port] "{dx}" (port),
    );
}

fn _inl(port: u16) u32 {
    return asm volatile ("inl %[port], %[result]"
        : [result] "={eax}" (-> u32),
        : [port] "N{dx}" (port),
    );
}

fn _outl(port: u16, data: u32) void {
    asm volatile ("outl %[data], %[port]"
        :
        : [data] "{eax}" (data),
          [port] "{dx}" (port),
    );
}

pub fn inb(port: anytype) u8 {
    return switch (@TypeOf(port)) {
        Ports, @TypeOf(.enum_literal) => _inb(@intFromEnum(@as(Ports, port))),
        u8, u16, u32, usize, comptime_int => _inb(@truncate(port)),
        else => @compileError("Invalid port type"),
    };
}

pub fn outb(port: anytype, data: u8) void {
    return switch (@TypeOf(port)) {
        Ports, @TypeOf(.enum_literal) => _outb(@intFromEnum(@as(Ports, port)), data),
        u8, u16, u32, usize, comptime_int => _outb(@truncate(port), data),
        else => @compileError("Invalid port type"),
    };
}

pub fn inw(port: anytype) u16 {
    return switch (@TypeOf(port)) {
        Ports, @TypeOf(.enum_literal) => _inw(@intFromEnum(@as(Ports, port))),
        u8, u16, u32, usize, comptime_int => _inw(@truncate(port)),
        else => @compileError("Invalid port type"),
    };
}

pub fn outw(port: usize, data: u16) void {
    return switch (@TypeOf(port)) {
        Ports, @TypeOf(.enum_literal) => _outw(@intFromEnum(@as(Ports, port)), data),
        u8, u16, u32, usize, comptime_int => _outw(@truncate(port), data),
        else => @compileError("Invalid port type"),
    };
}

pub fn inl(port: anytype) u32 {
    return switch (@TypeOf(port)) {
        Ports, @TypeOf(.enum_literal) => _inl(@intFromEnum(@as(Ports, port))),
        u8, u16, u32, usize, comptime_int => _inl(@truncate(port)),
        else => @compileError("Invalid port type"),
    };
}

pub fn outl(port: anytype, data: u32) void {
    return switch (@TypeOf(port)) {
        Ports, @TypeOf(.enum_literal) => _outl(@intFromEnum(@as(Ports, port)), data),
        u8, u16, u32, usize, comptime_int => _outl(@truncate(port), data),
        else => @compileError("Invalid port type"),
    };
}
