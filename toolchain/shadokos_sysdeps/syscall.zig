// ShadokOS syscall glue for mlibc (i386, int 0x80).
//
// Kernel ABI: syscall number in eax, arguments in ebx/ecx/edx/esi/edi/ebp,
// return value in eax, errno in ebx (0 on success).
//
// The C++ sysdeps shim sees the usual collapsed convention instead:
// a non-negative return value on success, -errno on failure. This is
// unambiguous because user virtual addresses stay below 0xc0000000, so
// only genuine errno values can land in [-4095, -1].
//
// Callers with fewer than six arguments go through the __shadokos_syscallN
// helpers in bits/syscall.h, which pad the rest with zeros.

export fn __shadokos_syscall(n: isize, a0: isize, a1: isize, a2: isize, a3: isize, a4: isize, a5: isize) isize {
    var ret: usize = undefined;
    var err: usize = undefined;
    // ebp is both the frame pointer and the 6th argument register, so it is
    // staged through the stack (same dance as musl's i386 __syscall6).
    asm volatile (
        \\push %[a5]
        \\push %%ebp
        \\mov 4(%%esp), %%ebp
        \\int $0x80
        \\pop %%ebp
        \\add $4, %%esp
        : [ret] "={eax}" (ret),
          [err] "={ebx}" (err),
        : [n] "{eax}" (n),
          [a0] "{ebx}" (a0),
          [a1] "{ecx}" (a1),
          [a2] "{edx}" (a2),
          [a3] "{esi}" (a3),
          [a4] "{edi}" (a4),
          [a5] "rm" (a5),
        : .{ .memory = true });
    return if (err != 0) -@as(isize, @intCast(err)) else @bitCast(ret);
}
