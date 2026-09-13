#include <unistd.h>

int main(int ac, char **av) {
	(void)setsid();

	if (ac > 1) {
		execvp(av[1], av + 1);
	} else {
		execvp("/bin/dash", (char*[]){"/bin/dash"});
	}
}
