#include <stdio.h>
#include <unistd.h>
#define MSG(msg) write(1, msg, sizeof(msg) - 1)

__attribute__((constructor(101))) void _c101(void) { MSG("constructor(101)\n"); }
__attribute__((constructor))      void _c(void)    { MSG("constructor\n"); }
__attribute__((destructor(101))) void _d101() { MSG("destructor(101)\n"); }
__attribute__((destructor)) void _d() { MSG("destructor\n"); }

int main(int argc, char *argv[])
{
	printf("Hello from mlibc!\n");
	return 0;
}

