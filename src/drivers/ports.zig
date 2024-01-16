pub const Ports = enum(u16) {
	keyboard_data = 0x60,
	keyboard_status = 0x64,
	vga_idx_reg = 0x03d4,
	vga_io_reg = 0x03d5
};

pub fn inb(port: Ports) u8 {
    return asm volatile("inb %[port], %[result]" : [result] "={al}" (-> u8) : [port] "N{dx}" (port));
}

pub fn outb(port: Ports, data: u8) void {
	asm volatile("outb %[data], %[port]" : : [data] "{al}" (data), [port] "{dx}" (port));
}

pub fn inw(port: Ports) u16 {
	return asm volatile("inw %[port], %[result]" : [result] "={ax}" (-> u16) : [port] "N{dx}" (port));
}

pub fn outw(port: Ports, data: u16) void {
	asm volatile("outw %[data], %[port]" : : [data] "{ax}" (data), [port] "{dx}" (port));
}

pub fn inl(port: Ports) u32 {
	return asm volatile("inl %[port], %[result]" : [result] "={eax}" (-> u32) : [port] "N{dx}" (port));
}

pub fn outl(port: Ports, data: u32) void {
	asm volatile("outl %[data], %[port]" : : [data] "{eax}" (data), [port] "{dx}" (port));
}