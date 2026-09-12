#ifndef _ABIBITS_TERMIOS_H
#define _ABIBITS_TERMIOS_H

typedef unsigned char cc_t;
typedef unsigned int tcflag_t;

/* indices for the c_cc array in struct termios */
#define NCCS     11
#define VEOF    0
#define VEOL    1
#define VERASE   2
#define VINTR    3
#define VKILL     4
#define VMIN    5
#define VQUIT     6
#define VSTART    7
#define VSTOP   8
#define VSUSP    9
#define VTIME    10

/* bitwise flags for c_iflag in struct termios */
#define BRKINT (1 << 0)
#define ICRNL (1 << 1)
#define IGNBRK (1 << 2)
#define IGNCR (1 << 3)
#define IGNPAR (1 << 4)
#define INLCR (1 << 5)
#define INPCK (1 << 6)
#define ISTRIP (1 << 7)
#define IXANY (1 << 8)
#define IXOFF (1 << 9)
#define IXON (1 << 10)
#define PARMRK (1 << 11)

/* bitwise flags for c_oflag in struct termios */
#define OPOST (1 << 0)
#define OLCUC (1 << 1)
#define ONLCR (1 << 2)
#define OCRNL (1 << 3)
#define ONOCR (1 << 4)
#define ONLRET (1 << 5)
#define OFILL (1 << 6)
#define OFDEL (1 << 7)

#define NLDLY (1 << 8)
#define NL0 0
#define NL1 (1 << 8)

#define CRDLY (0b11 << 9)
#define CR0 0
#define CR1 (0b01 << 9)
#define CR2 (0b10 << 9)
#define CR3 (0b11 << 9)

#define TABDLY (0b11 << 11)
#define TAB0 0
#define TAB1 (0b01 << 11)
#define TAB2 (0b10 << 11)
#define TAB3 (0b11 << 11)

#define BSDLY (1 << 13)
#define BS0 0
#define BS1 (1 << 13)

#define FFDLY (1 << 14)
#define FF0 0
#define FF1 (1 << 14)


#define VTDLY (1 << 15)
#define VT0 0
#define VT1 (1 << 15)

/* bitwise constants for c_cflag in struct termios */
#define CSIZE 0b11
#define CS5 0
#define CS6 0b01
#define CS7 0b10
#define CS8 0b11

#define CSTOPB (1 << 2)
#define CREAD (1 << 3)
#define PARENB (1 << 4)
#define PARODD (1 << 5)
#define HUPCL (1 << 6)
#define CLOCAL (1 << 7)

/* bitwise constants for c_lflag in struct termios */
#define ECHO (1 << 0)
#define ECHOE (1 << 1)
#define ECHOK (1 << 2)
#define ECHONL (1 << 3)
#define ICANON (1 << 4)
#define IEXTEN (1 << 5)
#define ISIG (1 << 6)
#define NOFLSH (1 << 7)
#define TOSTOP (1 << 8)

struct termios {
	tcflag_t c_iflag;
	tcflag_t c_oflag;
	tcflag_t c_cflag;
	tcflag_t c_lflag;
	cc_t c_cc[NCCS];
};

#endif
