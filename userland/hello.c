#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[])
{
	char name[64];

	printf("Hello from mlibc! (argc=%d)\n", argc);
	for (int i = 0; i < argc; i++)
		printf("argv[%d] = \"%s\"\n", i, argv[i]);

	void *p = malloc(1);
	printf("malloc: %p\n", p);
	free(p);

	printf("What's your name? ");
	fflush(stdout);
	if (fgets(name, sizeof(name), stdin)) {
		name[strcspn(name, "\n")] = 0;
		printf("Nice to meet you, %s!\n", name);
	}
	return 0;
}
