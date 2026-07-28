#include <stdio.h>

__attribute__((constructor(101))) void _c101(void) { printf("constructor(%d): %s\n", 101, "test de printf lol"); }
__attribute__((constructor))      void _c(void)    { printf("constructor\n"); }
__attribute__((destructor(101)))  void _d101(void) { printf("destructor(101)\n"); }
__attribute__((destructor))       void _d(void)    { printf("destructor\n"); }

int main(void)
{
	printf("main\n");
	return 0;
}
