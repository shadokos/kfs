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

pub fn read_tsc_safe() u64 {
    var low: u32 = undefined;
    var high: u32 = undefined;

    // Barrière mémoire pour empêcher la réorganisation d'instructions
    asm volatile ("cpuid" ::: "eax", "ebx", "ecx", "edx", "memory");

    asm volatile ("rdtsc"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
        :
        : "memory"
    );

    return (@as(u64, high) << 32) | @as(u64, low);
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

/// Reads the current CPU flags register (EFLAGS/RFLAGS)
pub inline fn read_flags() usize {
    if (@sizeOf(usize) == 8) {
        // 64-bit mode
        return asm volatile ("pushfq; popq %[flags]"
            : [flags] "=r" (-> u64),
        );
    } else {
        // 32-bit mode
        return asm volatile ("pushfl; popl %[flags]"
            : [flags] "=r" (-> u32),
        );
    }
}

/// Writes to the CPU flags register (EFLAGS/RFLAGS)
pub inline fn write_flags(flags: usize) void {
    if (@sizeOf(usize) == 8) {
        // 64-bit mode
        asm volatile ("pushq %[flags]; popfq"
            :
            : [flags] "r" (flags),
            : "memory"
        );
    } else {
        // 32-bit mode
        asm volatile ("pushl %[flags]; popfl"
            :
            : [flags] "r" (flags),
            : "memory"
        );
    }
}

/// Disables interrupts (CLI instruction)
pub inline fn disable_interrupts() void {
    asm volatile ("cli" ::: "memory");
}

/// Enables interrupts (STI instruction)
pub inline fn enable_interrupts() void {
    asm volatile ("sti" ::: "memory");
}

/// Checks if interrupts are currently enabled
pub inline fn interrupts_enabled() bool {
    const flags = read_flags();
    return (flags & 0x200) != 0; // IF flag is bit 9 in both 32-bit and 64-bit
}

/// Saves current interrupt state and disables interrupts atomically
/// Returns the saved flags that should be passed to restore_interrupts()
pub inline fn save_and_disable_interrupts() usize {
    const flags = read_flags();
    disable_interrupts();
    return flags;
}

/// Restores interrupt state from saved flags
/// Use with the return value from save_and_disable_interrupts()
pub inline fn restore_interrupts(saved_flags: usize) void {
    write_flags(saved_flags);
}

/// Halt the CPU until next interrupt (HLT instruction)
pub inline fn halt() void {
    asm volatile ("hlt");
}

/// Pause instruction - hint to CPU that we're in a spin loop
/// Better than NOP for busy-waiting as it reduces power consumption
/// and can improve performance on hyperthreaded systems
pub inline fn pause() void {
    asm volatile ("pause");
}

/// No-operation instruction
pub inline fn nop() void {
    asm volatile ("nop");
}

/// Memory barrier - ensures all memory operations complete before proceeding
pub inline fn memory_barrier() void {
    asm volatile ("" ::: "memory");
}

/// Full memory fence (MFENCE instruction)
pub inline fn memory_fence() void {
    asm volatile ("mfence" ::: "memory");
}

/// Read Time Stamp Counter (RDTSC instruction)
/// Returns the number of CPU cycles since reset
/// Note: On modern CPUs, this is usually invariant TSC (constant frequency)
pub inline fn rdtsc() u64 {
    var low: u32 = undefined;
    var high: u32 = undefined;

    asm volatile ("rdtsc"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
    );

    return (@as(u64, high) << 32) | @as(u64, low);
}

/// Read Time Stamp Counter and Processor ID (RDTSCP instruction)
/// Like RDTSC but also returns processor ID and is serializing
/// Returns: { tsc_value, processor_id }
pub inline fn rdtscp() struct { tsc: u64, processor_id: u32 } {
    var low: u32 = undefined;
    var high: u32 = undefined;
    var aux: u32 = undefined;

    asm volatile ("rdtscp"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
          [aux] "={ecx}" (aux),
    );

    return .{
        .tsc = (@as(u64, high) << 32) | @as(u64, low),
        .processor_id = aux,
    };
}

/// Serializing RDTSC - ensures all prior instructions complete before reading TSC
/// More precise but slower than regular RDTSC
pub inline fn rdtsc_serialized() u64 {
    // CPUID is a serializing instruction
    asm volatile ("cpuid" ::: "eax", "ebx", "ecx", "edx");
    const tsc = rdtsc();
    asm volatile ("cpuid" ::: "eax", "ebx", "ecx", "edx");
    return tsc;
}

/// CPU identification using CPUID instruction
pub const CpuId = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

/// Execute CPUID instruction with given leaf/subleaf
pub inline fn cpuid(leaf: u32, subleaf: u32) CpuId {
    var eax: u32 = 0;
    var ebx: u32 = 0;
    var ecx: u32 = 0;
    var edx: u32 = 0;

    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [leaf] "{eax}" (leaf),
          [subleaf] "{ecx}" (subleaf),
    );

    return .{
        .eax = eax,
        .ebx = ebx,
        .ecx = ecx,
        .edx = edx,
    };
}

/// Check if TSC is available and invariant
pub fn tsc_available() bool {
    // Check if RDTSC is supported (bit 4 in EDX of CPUID leaf 1)
    const basic_info = cpuid(1, 0);
    if ((basic_info.edx & (1 << 4)) == 0) {
        return false;
    }

    // Check if invariant TSC is supported (bit 8 in EDX of CPUID leaf 0x80000007)
    const extended_info = cpuid(0x80000007, 0);
    return (extended_info.edx & (1 << 8)) != 0;
}

/// Get TSC frequency from CPUID if available (Intel only)
/// Returns 0 if not available
pub fn get_tsc_frequency_from_cpuid() u64 {
    // Check if TSC frequency is available (leaf 0x15)
    const max_leaf = cpuid(0, 0).eax;
    if (max_leaf < 0x15) return 0;

    const tsc_info = cpuid(0x15, 0);
    if (tsc_info.eax == 0 or tsc_info.ebx == 0) return 0;

    // Calculate frequency: crystal_freq * ebx / eax
    // If ecx is 0, we need to determine crystal frequency another way
    const crystal_freq = if (tsc_info.ecx != 0) tsc_info.ecx else blk: {
        // Try to determine crystal frequency from processor info
        const proc_info = cpuid(0x16, 0);
        if (proc_info.eax != 0) {
            // Assume crystal is base frequency / ratio
            break :blk proc_info.eax * 1_000_000; // Convert MHz to Hz
        }
        break :blk 0;
    };

    if (crystal_freq == 0) return 0;

    return (@as(u64, crystal_freq) * @as(u64, tsc_info.ebx)) / @as(u64, tsc_info.eax);
}

/// Convenience function for your PIT driver
/// Alias for rdtsc() to match your existing code
pub inline fn read_tsc() u64 {
    return rdtsc();
}

// Test/debug functions

/// Measure TSC overhead by reading it twice
pub fn measure_tsc_overhead() u64 {
    const start = rdtsc();
    const end = rdtsc();
    return end -% start;
}

/// Benchmark function timing
pub fn benchmark_function(comptime func: anytype, iterations: u32) struct {
    avg_cycles: u64,
    min_cycles: u64,
    max_cycles: u64,
} {
    var total_cycles: u64 = 0;
    var min_cycles: u64 = @as(u64, @bitCast(@as(i64, -1))); // Max value
    var max_cycles: u64 = 0;

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const start = rdtsc();
        func();
        const end = rdtsc();

        const cycles = end -% start;
        total_cycles += cycles;

        if (cycles < min_cycles) min_cycles = cycles;
        if (cycles > max_cycles) max_cycles = cycles;
    }

    return .{
        .avg_cycles = total_cycles / iterations,
        .min_cycles = min_cycles,
        .max_cycles = max_cycles,
    };
}
