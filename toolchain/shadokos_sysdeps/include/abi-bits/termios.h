#ifndef _ABIBITS_TERMIOS_H
#define _ABIBITS_TERMIOS_H

/* The ShadokOS terminal ABI. It is not Linux's and is not meant to be: c_cc
 * holds only the characters the line discipline reads, the flags are numbered
 * from zero in the order the kernel declares them, and the line speed is bits
 * per second in a field of its own rather than an index tucked into c_cflag.
 *
 * This has to stay the exact shape of `abi.Termios` in
 * kernel/src/tty/termios.zig; nothing translates between the two. */

typedef unsigned char cc_t;
typedef unsigned int speed_t;
typedef unsigned int tcflag_t;

/* indices for the c_cc array in struct termios */
#define NCCS   11
#define VEOF   0
#define VEOL   1
#define VERASE 2
#define VINTR  3
#define VKILL  4
#define VMIN   5
#define VQUIT  6
#define VSTART 7
#define VSTOP  8
#define VSUSP  9
#define VTIME  10

/* bitwise flags for c_iflag in struct termios */
#define ISTRIP (1 << 0)
#define ICRNL  (1 << 1)
#define INLCR  (1 << 2)
#define IGNCR  (1 << 3)
#define BRKINT (1 << 4)
#define IGNBRK (1 << 5)
#define IGNPAR (1 << 6)
#define INPCK  (1 << 7)
#define PARMRK (1 << 8)
#define IXON   (1 << 9)
#define IXOFF  (1 << 10)
#define IXANY  (1 << 11)

/* bitwise flags for c_oflag in struct termios */
#define OPOST  (1 << 0)
#define ONLCR  (1 << 1)
#define OCRNL  (1 << 2)
#define ONLRET (1 << 3)
#define OLCUC  (1 << 4)
#define ONOCR  (1 << 5)
#define OFILL  (1 << 6)
#define OFDEL  (1 << 7)

/* The output delays a teletype needed. A screen has none, so they are all the
 * one value POSIX lets them be. */
#define NLDLY  0
#define NL0    0
#define NL1    0
#define CRDLY  0
#define CR0    0
#define CR1    0
#define CR2    0
#define CR3    0
#define TABDLY 0
#define TAB0   0
#define TAB1   0
#define TAB2   0
#define TAB3   0
#define BSDLY  0
#define BS0    0
#define BS1    0
#define FFDLY  0
#define FF0    0
#define FF1    0
#define VTDLY  0
#define VT0    0
#define VT1    0

/* bitwise constants for c_cflag in struct termios */
#define CSIZE  (1 << 0)
#define CSTOPB (1 << 1)
#define CREAD  (1 << 2)
#define PARENB (1 << 3)
#define PARODD (1 << 4)
#define HUPCL  (1 << 5)
#define CLOCAL (1 << 6)

/* Character size is a single bit here: a console moves whole bytes, so the
 * only width the ABI can name is eight. */
#define CS5 0
#define CS6 0
#define CS7 0
#define CS8 CSIZE

/* bitwise constants for c_lflag in struct termios */
#define ICANON  (1 << 0)
#define ECHO    (1 << 1)
#define ECHOE   (1 << 2)
#define ECHOK   (1 << 3)
#define ECHONL  (1 << 4)
#define ECHOCTL (1 << 5)
#define ISIG    (1 << 6)
#define NOFLSH  (1 << 7)
#define IEXTEN  (1 << 8)
#define TOSTOP  (1 << 9)

/* The speed of the line, which a console does not have. No bit of c_cflag
 * carries one, so cfgetospeed reads back B0 and cfsetospeed takes nothing
 * else -- the same answer the kernel gives, which writes zero into c_ibaud
 * and c_obaud and reads neither back. Those two fields are the room the ABI
 * keeps for the day a real line needs a speed; the speed will be the speed
 * itself and not an index, and the B* names in <termios.h> are then the ones
 * to stop believing. */
#define CBAUD 0

struct termios {
	tcflag_t c_iflag;
	tcflag_t c_oflag;
	tcflag_t c_cflag;
	tcflag_t c_lflag;
	cc_t c_cc[NCCS];
	speed_t c_ibaud;
	speed_t c_obaud;
};

#endif
