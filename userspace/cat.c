#include <fcntl.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>


void cat(char *f) {
	int fd = 0;
	if (strcmp(f, "-")) {
		fd = open(f, O_RDONLY);
	}
	char buffer[4096];
	ssize_t ret;
	while ((ret = read(fd, buffer, sizeof(buffer))) > 0) {
		if (write(1, buffer, ret) != ret) {
			perror("cat");
			exit(1);
		}
	}
}

int main(int ac, char **av) {
	if (ac == 1) {
		cat("-");
	} else {
		for (int i = 1; i < ac; i++) {
			cat(av[i]);
		}
	}
}
