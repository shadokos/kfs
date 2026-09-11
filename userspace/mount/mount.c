
long __shadokos_syscall(long n, long a0, long a1, long a2, long a3, long a4, long a5);
static inline long __shadokos_syscall3(long n, long a0, long a1, long a2) {
	return __shadokos_syscall(n, a0, a1, a2, 0, 0, 0);
}
int main() {
	__shadokos_syscall3(55, (long)(void*)"/dev", (long)(void*)".virtual", (long)(void*)"devfs");
}
