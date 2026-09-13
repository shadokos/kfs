#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <pwd.h>

#define MAX_ATTEMPT 3
#define PASSWORD_FILE "/etc/passwd"

void spawn(struct passwd *pwd, char **av) {
	setenv("USER", pwd->pw_name, 1);
	setenv("HOME", pwd->pw_dir, 1);
	if (setreuid(pwd->pw_uid, pwd->pw_uid) == -1 ||
		setregid(pwd->pw_gid, pwd->pw_gid) == -1) {
		perror("su");
		exit(1);
	}
	av[0] = pwd->pw_shell;
	execvp(pwd->pw_shell, av);
	perror("su: Failed to spawn shell");
	exit(1);
}

bool prompt(char *dst, size_t size) {
	fprintf(stderr, "Please enter password\n");
	if (!fgets(dst, size - 1, stdin))
		return false;
	char *newline = strchr(dst, '\n');
	*newline = 0;
	return true;
}

int main(int ac, char **av) {
	if (ac < 2) {
		fprintf(stderr, "Invalid number of argument\n");
		return 1;
	}
	char *username = av[1];
	char password[100];
	int attempt = 0;

	struct passwd *pwd = getpwnam(username);

	if (!pwd)
		return 1;
	
	while (prompt(password, sizeof(password))) {
		if (!strcmp(password, pwd->pw_passwd)) {
			spawn(pwd, av + 1);
		}
		if (++attempt == MAX_ATTEMPT) {
			fprintf(stderr, "Too many attempts\n");
			return 1;
		}
	}
}
