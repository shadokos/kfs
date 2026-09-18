#include <stdio.h>
#include <sys/types.h>
#include <pwd.h>
#include <unistd.h>

int main() {
	uid_t uid = getuid();

	struct passwd *pwd = getpwuid(uid);
	if (!pwd)
		return 1;
	printf("%s\n", pwd->pw_name);
}
