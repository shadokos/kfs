#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

int main() {
	int fd = open("/dev/tty0", O_RDWR);
	dup2(fd, 0);
	dup2(fd, 1);
	dup2(fd, 2);
	printf("bonjour, monde\n");
	return 42;
}

