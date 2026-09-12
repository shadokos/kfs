#ifndef _ABIBITS_WAIT_H
#define _ABIBITS_WAIT_H

#include <mlibc-config.h>

#define WCONTINUED 1
#define WNOHANG 2
#define WUNTRACED 4
//#define WSTOPPED 2
//#define WEXITED 4
//#define WNOWAIT 0x01000000

#define WEXITSTATUS(x) (((x) & 0xff00) >> 8)
#define WTERMSIG(x) WEXITSTATUS(x)
#define WSTOPSIG(x) WEXITSTATUS(x)
#define WIFEXITED(x) ((x & 0xff) == 1)
#define WIFSTOPPED(x) ((x & 0xff) == 2)
#define WIFCONTINUED(x) ((x & 0xff) == 3)
#define WIFSIGNALED(x) ((x & 0xff) == 4)

#endif /*_ABIBITS_WAIT_H */
