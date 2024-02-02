const k = @import("../keymap.zig");

pub const keymap = [_][6]u16 {
	//			!SHIFT		SHIFT		ALT1		ALT2		ALT+SHIFT 	CTRL		//
	// ================================================================================	//
	[6]u16 {	0, 			0, 			0, 			0, 			0,			0 			},	// 0x0  NONE
	[6]u16 {	0, 			0, 			0, 			0, 			0,			0 			},	// 0x1  NONE
	[6]u16 {	0, 			0, 			0, 			0, 			0,			0 			},	// 0x2  NONE
	[6]u16 {	0, 			0, 			0, 			0, 			0,			0 			},	// 0x3  NONE
	[6]u16 { 	k.L('q'), 	'Q', 		k.A('q'), 	'q', 		'Q',	 	k.C('Q') 	},	// 0x4	Key Q
	[6]u16 { 	k.L('b'), 	'B', 		k.A('b'), 	'b', 		'B',	 	k.C('B') 	},	// 0x5  Key B
	[6]u16 { 	k.L('c'), 	'C', 		k.A('c'), 	'c', 		'C',	 	k.C('C') 	},	// 0x6  Key C
	[6]u16 { 	k.L('d'), 	'D', 		k.A('d'), 	'd', 		'D',	 	k.C('D') 	},	// 0x7  Key D
	[6]u16 { 	k.L('e'), 	'E', 		k.A('e'), 	'e', 		'E',	 	k.C('E') 	},	// 0x8  Key E
	[6]u16 { 	k.L('f'), 	'F', 		k.A('f'), 	'f', 		'F',	 	k.C('F') 	},	// 0x9  Key F
	[6]u16 { 	k.L('g'), 	'G', 		k.A('g'), 	'g', 		'G',	 	k.C('G') 	},	// 0xa  Key G
	[6]u16 { 	k.L('h'), 	'H', 		k.A('h'), 	'h', 		'H',	 	k.C('H') 	},	// 0xb  Key H
	[6]u16 { 	k.L('i'), 	'I', 		k.A('i'), 	'i', 		'I',	 	k.C('I') 	},	// 0xc  Key I
	[6]u16 { 	k.L('j'), 	'J', 		k.A('j'), 	'j', 		'J',	 	k.C('J') 	},	// 0xd  Key J
	[6]u16 { 	k.L('k'), 	'K', 		k.A('k'), 	'k', 		'K',	 	k.C('K') 	},	// 0xe  Key K
	[6]u16 { 	k.L('l'), 	'L', 		k.A('l'), 	'l', 		'L',	 	k.C('L') 	},	// 0xf  Key L
	[6]u16 { 	',',		'?',		k.A(','),	',',		'm',		k.C('@') 	},	// 0x10 Key N
	[6]u16 { 	k.L('n'), 	'N', 		k.A('n'), 	'n', 		'N',	 	k.C('N') 	},	// 0x11 Key N
	[6]u16 { 	k.L('o'), 	'O', 		k.A('o'), 	'o', 		'O',	 	k.C('O') 	},	// 0x12 Key O
	[6]u16 { 	k.L('p'), 	'P', 		k.A('p'), 	'p', 		'P',	 	k.C('P') 	},	// 0x13 Key P
	[6]u16 { 	k.L('a'),	'A', 		k.A('a'), 	'a', 		'A',	 	k.C('A') 	},	// 0x14 Key A
	[6]u16 { 	k.L('r'), 	'R', 		k.A('r'), 	'r', 		'R',	 	k.C('R') 	},	// 0x15 Key R
	[6]u16 { 	k.L('s'), 	'S', 		k.A('s'), 	's', 		'S',	 	k.C('S') 	},	// 0x16 Key S
	[6]u16 { 	k.L('t'), 	'T', 		k.A('t'), 	't', 		'T',	 	k.C('T') 	},	// 0x17 Key T
	[6]u16 { 	k.L('u'), 	'U', 		k.A('u'), 	'u', 		'U',	 	k.C('U') 	},	// 0x18 Key U
	[6]u16 { 	k.L('v'), 	'V', 		k.A('v'), 	'v', 		'V',	 	k.C('V') 	},	// 0x19 Key V
	[6]u16 { 	k.L('z'), 	'Z', 		k.A('z'), 	'z', 		'Z',	 	k.C('Z') 	},	// 0x1a Key Z
	[6]u16 { 	k.L('x'), 	'X', 		k.A('x'), 	'x', 		'X',	 	k.C('X') 	},	// 0x1b Key X
	[6]u16 { 	k.L('y'), 	'Y', 		k.A('y'), 	'y', 		'Y',	 	k.C('Y') 	},	// 0x1c Key Y
	[6]u16 { 	k.L('w'), 	'W', 		k.A('w'), 	'w', 		'W',	 	k.C('W') 	},	// 0x1d Key W
	[6]u16 {	'&', 		'1',		k.A('1'),	'&',		'1',		k.C('A')	},	// 0x1e Key 1
	[6]u16 {	0o202, 		'2',		k.A('2'),	'~',		'2',		k.C('B')	},	// 0x1f Key 2
	[6]u16 {	'"', 		'3',		k.A('3'),	'#',		'3',		k.C('C')	},	// 0x20 Key 3
	[6]u16 {	'\'', 		'4',		k.A('4'),	'{',		'4',		k.C('D')	},	// 0x21 Key 4
	[6]u16 {	'(', 		'5',		k.A('5'),	'[',		'5',		k.C('E')	},	// 0x22 Key 5
	[6]u16 {	'-', 		'6',		k.A('6'),	'|',		'6',		k.C('F')	},	// 0x23 Key 6
	[6]u16 {	0o212, 		'7',		k.A('7'),	'`',		'7',		k.C('G')	},	// 0x24 Key 7
	[6]u16 {	'_', 		'8',		k.A('8'),	'\\',		'8',		k.C('H')	},	// 0x25 Key 8
	[6]u16 {	0o207, 		'9',		k.A('9'),	'^',		'9',		k.C('I')	},	// 0x26 Key 9
	[6]u16 {	0o205, 		'0',		k.A('0'),	'@',		'0',		k.C('J')	},	// 0x27 Key 0
	[6]u16 { 	k.C('M'), 	k.C('M'), 	k.CA('M'), 	k.C('M'), 	k.C('M'), 	k.C('M')	},	// 0x28 Key ENTER
	[6]u16 {	k.C('['),	k.C('['),	k.CA('['),	k.C('['),	k.C('['),	k.C('[')	},	// 0x29 Key ESC
	[6]u16 {	k.C('H'),	k.C('H'),	k.CA('H'),	k.C('H'),	k.C('H'),	127			}, 	// 0x2a Key BACKSPACE
	[6]u16 {	k.C('I'),	k.C('I'),	k.CA('I'),	k.C('I'),	k.C('I'),	k.C('I')	},	// 0x2b Key TAB
	[6]u16 {	' ',		' ',		k.A(' '),	k.A(' '),	k.A(' '),	k.C('@')	},	// 0x2c Key SPACEBAR
	[6]u16 {	')',		0o370,		k.A(')'),	']',		'-',		k.C('K')	},
	[6]u16 {	'=',		'+',		k.A('='),	'}',		'=',		k.C('L')	},
	[6]u16 {	'^',		'"',		k.A('^'),	'^',		'[',		k.C('^')	},
	[6]u16 {	'$',		0o234,		k.A('$'),	'$',		']',		k.C('$')	},
	[6]u16 {	'*',		0o346,		k.A('*'),	'*',		'`',		k.C('*')	},
	[6]u16 {	0, 			0, 			0, 			0, 			0, 			0			},	// 0x32 Key ??
	[6]u16 {	k.L('m'),	'M',		k.A('m'),	'm',		'M',		k.C('M')	},
	[6]u16 {	0o227,		'%',		k.A('%'),	0o227,		'\\',		k.C('G')	},
	[6]u16 {	0o375,		0o375,		0o375,		0o375,		'`',		k.C('[')	},
	[6]u16 {	';',		'.',		k.A(';'),	';',		',',		k.C('@')	},
	[6]u16 {	':',		'/',		k.A(':'),	':',		'.',		k.C('@')	},
	[6]u16 {	'!',		'$',		k.A('!'),	'!',		'/',		k.C('@')	},
	[6]u16 {	k.CALOCK,	k.CALOCK,	k.CALOCK,	k.CALOCK,	k.CALOCK,	k.CALOCK	},	// 0x39 Key CAPS_LOCK
	[6]u16 {	k.F1,		k.SF1,		k.AF1,		k.AF1,		k.ASF1,		k.CF1		},	// 0x3a Key F1
	[6]u16 {	k.F2,		k.SF2,		k.AF2,		k.AF2,		k.ASF2,		k.CF2		},	// 0x3b Key F2
	[6]u16 {	k.F3,		k.SF3,		k.AF3,		k.AF3,		k.ASF3,		k.CF3		},	// 0x3c Key F3
	[6]u16 {	k.F4,		k.SF4,		k.AF4,		k.AF4,		k.ASF4,		k.CF4		},	// 0x3d Key F4
	[6]u16 {	k.F5,		k.SF5,		k.AF5,		k.AF5,		k.ASF5,		k.CF5		},	// 0x3e Key F5
	[6]u16 {	k.F6,		k.SF6,		k.AF6,		k.AF6,		k.ASF6,		k.CF6		},	// 0x3f Key F6
	[6]u16 {	k.F7,		k.SF7,		k.AF7,		k.AF7,		k.ASF7,		k.CF7		},	// 0x40 Key F7
	[6]u16 {	k.F8,		k.SF8,		k.AF8,		k.AF8,		k.ASF8,		k.CF8		},	// 0x41 Key F8
	[6]u16 {	k.F9,		k.SF9,		k.AF9,		k.AF9,		k.ASF9,		k.CF9		},	// 0x42 Key F9
	[6]u16 {	k.F10,		k.SF10,		k.AF10,		k.AF10,		k.ASF10,	k.CF10		},	// 0x43 Key F10
	[6]u16 {	k.F11,		k.SF11,		k.AF11,		k.AF11,		k.ASF11,	k.CF11		},	// 0x44 Key F11
	[6]u16 {	k.F12,		k.SF12,		k.AF12,		k.AF12,		k.ASF12,	k.CF12		},	// 0x45 Key F12
	[6]u16 {	0, 			0, 			0, 			0, 			0, 			0			},	// 0x46 Key ??
	[6]u16 {	k.SLOCK,	k.SLOCK,	k.SLOCK,	k.SLOCK,	k.SLOCK,	k.SLOCK		},	// 0x47 Key SCROLL_LOCK
	[6]u16 {	0, 			0, 			0, 			0, 			0, 			0			},	// 0x48 Key ??
	[6]u16 {	k.INSRT,	k.INSRT,	k.AINSRT,	k.AINSRT,	k.AINSRT,	k.CINSRT	},	// 0x49 Key INSERT
	[6]u16 {	k.HOME,		k.HOME,		k.AHOME,	k.AHOME,	k.AHOME,	k.CHOME		},	// 0x4a Key HOME
	[6]u16 {	k.PGUP,		k.PGUP,		k.APGUP,	k.APGUP,	k.APGUP,	k.CPGUP		},	// 0x4b Key PAGE_UP
	[6]u16 {	k.DEL,		k.DEL,		k.A(k.DEL),	k.DEL,		k.A(k.DEL),	k.DEL		},	// 0x4c Key DELETE
	[6]u16 {	k.END,		k.END,		k.AEND,		k.AEND,		k.AEND,		k.CEND		},	// 0x4d Key END
	[6]u16 {	k.PGDN,		k.PGDN,		k.APGDN,	k.APGDN,	k.APGDN,	k.CPGDN		},	// 0x4e Key PAGE_DOWN
	[6]u16 {	k.RIGHT,	k.RIGHT,	k.ARIGHT,	k.ARIGHT,	k.ARIGHT,	k.CRIGHT	},	// 0x4f Key RIGHT_ARROW
	[6]u16 {	k.LEFT,		k.LEFT,		k.ALEFT,	k.ALEFT,	k.ALEFT,	k.CLEFT		},	// 0x50 Key LEFT_ARROW
	[6]u16 {	k.DOWN,		k.DOWN,		k.ADOWN,	k.ADOWN,	k.ADOWN,	k.CDOWN		},	// 0x51 Key DOWN_ARROW
	[6]u16 {	k.UP,		k.UP,		k.AUP,		k.AUP,		k.AUP,		k.CUP		},	// 0x52 Key UP_ARROW
	[6]u16 {	k.NLOCK,	k.NLOCK,	k.NLOCK,	k.NLOCK,	k.NLOCK,	k.NLOCK		},	// 0x53 Key NUM_LOCK
	[6]u16 {	'/',		'/',		k.A('/'),	k.A('/'),	'/',		k.C('@')	},
	[6]u16 {	'*',		'*',		k.A('*'),	'*',		'*',		k.C('@')	},
	[6]u16 {	'-',		'-',		k.AMIN,		k.AMIN,		'-',		k.CNMIN		},
	[6]u16 {	'+',		'+',		k.APLUS,	k.APLUS,	'+',		k.CPLUS		},
	[6]u16 {	k.C('M'),	k.C('M'),	k.CA('M'),	k.C('M'),	k.CA('M'),	k.C('J')	},
	[6]u16 {	k.NEND,		'1',		k.AEND,		k.AEND,		'1',		k.CEND		},
	[6]u16 {	k.NDOWN,	'2',		k.ADOWN,	k.ADOWN,	'2',		k.CDOWN		},
	[6]u16 {	k.NPGDN,	'3',		k.APGDN,	k.APGDN,	'3',		k.CPGDN		},
	[6]u16 {	k.NLEFT,	'4',		k.ALEFT,	k.ALEFT,	'4',		k.CLEFT		},
	[6]u16 {	k.NMID,		'5',		k.AMID,		k.AMID,		'5',		k.CMID		},
	[6]u16 {	k.NRIGHT,	'6',		k.ARIGHT,	k.ARIGHT,	'6',		k.CRIGHT	},
	[6]u16 {	k.NHOME,	'7',		k.AHOME,	k.AHOME,	'7',		k.CHOME		},
	[6]u16 {	k.NUP,		'8',		k.AUP,		k.AUP,		'8',		k.CUP		},
	[6]u16 {	k.NPGUP,	'9',		k.APGUP,	k.APGUP,	'9',		k.CPGUP		},
	[6]u16 {	k.NINSRT,	'0',		k.AINSRT,	k.AINSRT,	'0',		k.CINSRT	},
	[6]u16 {	k.NDEL,		'.',		k.A(k.DEL),	k.DEL,		'.',		k.DEL		},
	[6]u16 {	'<',		'>',		k.A('<'),	'<',		'>',		k.C('@')	},
	[6]u16 {	k.C('M'),	k.C('M'),	k.CA('M'),	k.C('M'),	k.C('M'),	k.C('J')	},
} ++ [_][6]u16 {
	[6]u16 {	0, 			0, 			0, 			0, 			0, 			0,			}
} ** 122 ++
[_][6]u16 {
	[6]u16 {	k.LCTRL,	k.LCTRL,	k.LCTRL,	k.LCTRL, 	k.LCTRL,	k.LCTRL		},	// 0xe0 Key LEFT_CTRL
	[6]u16 {	k.LSHIFT,	k.LSHIFT,	k.LSHIFT,	k.LSHIFT,	k.LSHIFT,	k.LSHIFT	},	// 0xe1 Key LEFT_SHIFT
	[6]u16 {	k.LALT,		k.LALT,	 	k.LALT,	 	k.LALT,	 	k.LALT,		k.LALT		},	// 0xe2 Key LEFT_ALT
	[6]u16 {	k.LEFT,		'<',	 	k.ALEFT,	k.ALEFT, 	k.A('<'),	k.CLEFT		},	// 0xe3 Key LEFT_GUI
	[6]u16 {	k.RCTRL,	k.RCTRL,	k.RCTRL,	k.RCTRL, 	k.RCTRL,	k.RCTRL		},	// 0xe4 Key RIGHT_CTRL
	[6]u16 {	k.RSHIFT,	k.RSHIFT,	k.RSHIFT,	k.RSHIFT,	k.RSHIFT,	k.RSHIFT	},	// 0xe5 Key RIGHT_SHIFT
	[6]u16 {	k.RALT,		k.RALT,	 	k.RALT,	 	k.RALT,	 	k.RALT,		k.RALT		},	// 0xe6 Key RIGHT_ALT
	[6]u16 {	k.RIGHT,	'>',	 	k.ARIGHT,	k.ARIGHT, 	k.A('>'),	k.CRIGHT	} 	// 0xe7 Key RIGHT_GUI
};
