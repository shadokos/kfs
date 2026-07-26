// ShadokOS C runtime entry point (i386).
//
// SysV i386: the kernel enters with argc/argv/envp/auxv laid out at esp.
// Zero ebp to mark the outermost frame, then hand the entry stack and
// main to __mlibc_entry(entry_stack, main_fn), cdecl, args pushed right
// to left.
//
export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\xor %%ebp, %%ebp
        \\mov %%esp, %%ecx
        \\push $main
        \\push %%ecx
        \\call __mlibc_entry
    );
}
