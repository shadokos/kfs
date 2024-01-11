pub const Ports = enum(u8) {
	keyboard_data = 0x60,
	keyboard_status = 0x64,
};

pub fn inb(port: Ports) u8 {
    return asm volatile("inb %[port], %[result]" : [result] "={al}" (-> u8) : [port] "N{dx}" (port));
}

pub fn outb(port: Ports, data: u8) void{
	asm volatile("outb %[data], %[port]" : : [data] "{al}" (data), [port] "{dx}" (port));
}