#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

long __shadokos_syscall(long n, long a0, long a1, long a2, long a3, long a4, long a5);
static inline long __shadokos_syscall3(long n, long a0, long a1, long a2) {
	return __shadokos_syscall(n, a0, a1, a2, 0, 0, 0);
}

int mount(char *path, char *part_identifier, char *fstype) {
	__shadokos_syscall3(55, (long)(void*)path, (long)(void*)part_identifier, (long)(void*)fstype);
}

int main(int ac, char **av) {
	if (ac < 3 || ac > 4)
		return 1;
	if (mount(av[1], av[2], av[3]) == -1) {
		perror(av[0]);
		exit(1);
	}
	return 0;
}
