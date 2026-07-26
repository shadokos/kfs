#ifndef _MLIBC_SYSCALL_H
#define _MLIBC_SYSCALL_H

/* ShadokOS syscall numbers */
#define SYS_SLEEP 1
#define SYS_WRITE 2
#define SYS_KILL 3
#define SYS_SIGRETURN 4
#define SYS_REBOOT 5
#define SYS_EXIT 6
#define SYS_FORK 7
#define SYS_SIGNAL 8
#define SYS_GETPID 9
#define SYS_GETPPID 10
#define SYS_SIGACTION 11
#define SYS_MMAP 12
#define SYS_MUNMAP 13
#define SYS_MPROTECT 14
#define SYS_GETUID 15
#define SYS_WAIT 16
#define SYS_WAITPID 17
#define SYS_OPEN 18
#define SYS_READ 19
#define SYS_SET_THREAD_AREA 20
#define SYS_TRUNCATE 21
#define SYS_MKDIR 22
#define SYS_SYMLINK 23
#define SYS_CLOSE 24
#define SYS_EXECVE 25

#ifdef __cplusplus
extern "C" {
#endif

/* Implemented in syscall.zig. Returns a non-negative value on success or
 * -errno on failure (the kernel's eax/ebx pair is collapsed there). */
long __shadokos_syscall(long n, long a0, long a1, long a2, long a3, long a4, long a5);

static inline long __shadokos_syscall0(long n) {
	return __shadokos_syscall(n, 0, 0, 0, 0, 0, 0);
}
static inline long __shadokos_syscall1(long n, long a0) {
	return __shadokos_syscall(n, a0, 0, 0, 0, 0, 0);
}
static inline long __shadokos_syscall2(long n, long a0, long a1) {
	return __shadokos_syscall(n, a0, a1, 0, 0, 0, 0);
}
static inline long __shadokos_syscall3(long n, long a0, long a1, long a2) {
	return __shadokos_syscall(n, a0, a1, a2, 0, 0, 0);
}
static inline long __shadokos_syscall4(long n, long a0, long a1, long a2, long a3) {
	return __shadokos_syscall(n, a0, a1, a2, a3, 0, 0);
}
static inline long __shadokos_syscall5(long n, long a0, long a1, long a2, long a3, long a4) {
	return __shadokos_syscall(n, a0, a1, a2, a3, a4, 0);
}
static inline long __shadokos_syscall6(long n, long a0, long a1, long a2, long a3, long a4, long a5) {
	return __shadokos_syscall(n, a0, a1, a2, a3, a4, a5);
}

#ifdef __cplusplus
}
#endif

#endif /* _MLIBC_SYSCALL_H */
