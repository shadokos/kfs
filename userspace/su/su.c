#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_ATTEMPT 3
#define PASSWORD_FILE "/etc/passwd"

void spawn(char *user, uid_t uid) {
	setenv("USER", user, 1);
	setreuid(uid, uid);
	setuid(uid);
	execvp("/bin/sh", (char*[]){"/bin/sh", NULL});
	perror("su: Failed to spawn shell");
	exit(1);
}

bool prompt(char *dst, size_t size) {
	fprintf(stderr, "Please enter password\n");
	return !!fgets(dst, size, stdin);
}

void login(char *username, char *password) {
	FILE *file = fopen(PASSWORD_FILE, "r");
	if (!file) {
		fprintf(stderr, "Cannot read password file\n");
		exit(1);
	}
	char buffer[100];
	while (fgets(buffer, sizeof(buffer), file)) {
		char *u = strtok(buffer, ":");
		char *p = strtok(NULL, ":");
		char *uid = strtok(NULL, ":");
		printf("%s %s %s\n", u, p, uid);
		exit(1);

		if (!u || strcmp(u, username))
			continue;
		if (!p || strcmp(p, password)) {
			return;
		}
		spawn(u, atoi(uid));

	}
}

int main(int ac, char **av) {
	if (ac < 2 || ac > 3) {
		fprintf(stderr, "Invalid number of argument\n");
		return 1;
	}
	char *username = av[1];
//	char password[100];
	char *password = av[2];
	int attempt = 0;
	
	while (true){//!prompt(password, sizeof(password))) {
		login(username, password);
		if (++attempt == MAX_ATTEMPT) {
			fprintf(stderr, "Too many attempts\n");
			return 1;
		}
	}
}
