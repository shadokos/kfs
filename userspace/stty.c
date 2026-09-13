#include <stdio.h>
#include <string.h>
#include <termios.h>

static void cooked(struct termios *t)
{
	t->c_iflag |= ICRNL | IXON;
	t->c_iflag &= ~(INLCR | IGNCR | ISTRIP);
	t->c_oflag |= OPOST | ONLCR;
	t->c_lflag |= ICANON | ECHO | ECHOE | ECHOK | ECHOCTL | ISIG | IEXTEN;
}

static void raw(struct termios *t)
{
	t->c_iflag &= ~(ICRNL | INLCR | IGNCR | ISTRIP | IXON);
	t->c_oflag &= ~OPOST;
	t->c_lflag &= ~(ICANON | ECHO | ECHOE | ECHOK | ECHOCTL | ISIG | IEXTEN);
	t->c_cc[VMIN] = 1;
	t->c_cc[VTIME] = 0;
}

int main(int ac, char **av)
{
	struct termios t;

	if (tcgetattr(0, &t) < 0) {
		perror("stty: standard input");
		return 1;
	}

	if (ac == 1) {
		printf("%s %sechoctl\n", (t.c_lflag & ICANON) ? "cooked" : "raw",
			(t.c_lflag & ECHOCTL) ? "" : "-");
		return 0;
	}

	for (int i = 1; i < ac; i++) {
		if (!strcmp(av[i], "raw") || !strcmp(av[i], "-cooked"))
			raw(&t);
		else if (!strcmp(av[i], "cooked") || !strcmp(av[i], "-raw"))
			cooked(&t);
		else if (!strcmp(av[i], "echoctl"))
			t.c_lflag |= ECHOCTL;
		else if (!strcmp(av[i], "-echoctl"))
			t.c_lflag &= ~ECHOCTL;
		else if (!strcmp(av[i], "echo"))
			t.c_lflag |= ECHO;
		else if (!strcmp(av[i], "-echo"))
			t.c_lflag &= ~ECHO;
		else {
			fprintf(stderr, "stty: unknown setting: %s\n", av[i]);
			return 1;
		}
	}

	if (tcsetattr(0, TCSAFLUSH, &t) < 0) {
		perror("stty");
		return 1;
	}
	return 0;
}
