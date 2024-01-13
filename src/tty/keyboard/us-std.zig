const k = @import("keymap.zig");

pub  const keymap = [_][6]u16 {
	//			!SHIFT		SHIFT		ALT1		ALT2		ALT+SHIFT 	CTRL		//
	// ================================================================================	//
	[6]u16 {	0, 			0, 			0, 			0, 			0,			0 			},	// 0x0  NONE
	[6]u16 {	0, 			0, 			0, 			0, 			0,			0 			},	// 0x1  NONE
	[6]u16 {	0, 			0, 			0, 			0, 			0,			0 			},	// 0x2  NONE
	[6]u16 {	0, 			0, 			0, 			0, 			0,			0 			},	// 0x3  NONE
	[6]u16 { 	k.L('a'),	'A', 		k.A('a'), 	k.A('A'), 	k.A('A'), 	k.C('A') 	},	// 0x4  Key A
	[6]u16 { 	k.L('b'), 	'B', 		k.A('b'), 	k.A('B'), 	k.A('B'), 	k.C('B') 	},	// 0x5  Key B
	[6]u16 { 	k.L('c'), 	'C', 		k.A('c'), 	k.A('C'), 	k.A('C'), 	k.C('C') 	},	// 0x6  Key C
	[6]u16 { 	k.L('d'), 	'D', 		k.A('d'), 	k.A('D'), 	k.A('D'), 	k.C('D') 	},	// 0x7  Key D
	[6]u16 { 	k.L('e'), 	'E', 		k.A('e'), 	k.A('E'), 	k.A('E'), 	k.C('E') 	},	// 0x8  Key E
	[6]u16 { 	k.L('f'), 	'F', 		k.A('f'), 	k.A('F'), 	k.A('F'), 	k.C('F') 	},	// 0x9  Key F
	[6]u16 { 	k.L('g'), 	'G', 		k.A('g'), 	k.A('G'), 	k.A('G'), 	k.C('G') 	},	// 0xa  Key G
	[6]u16 { 	k.L('h'), 	'H', 		k.A('h'), 	k.A('H'), 	k.A('H'), 	k.C('H') 	},	// 0xb  Key H
	[6]u16 { 	k.L('i'), 	'I', 		k.A('i'), 	k.A('I'), 	k.A('I'), 	k.C('I') 	},	// 0xc  Key I
	[6]u16 { 	k.L('j'), 	'J', 		k.A('j'), 	k.A('J'), 	k.A('J'), 	k.C('J') 	},	// 0xd  Key J
	[6]u16 { 	k.L('k'), 	'K', 		k.A('k'), 	k.A('K'), 	k.A('K'), 	k.C('K') 	},	// 0xe  Key K
	[6]u16 { 	k.L('l'), 	'L', 		k.A('l'), 	k.A('L'), 	k.A('L'), 	k.C('L') 	},	// 0xf  Key L
	[6]u16 { 	k.L('m'), 	'M', 		k.A('m'), 	k.A('M'), 	k.A('M'), 	k.C('M') 	},	// 0x10 Key M
	[6]u16 { 	k.L('n'), 	'N', 		k.A('n'), 	k.A('N'), 	k.A('N'), 	k.C('N') 	},	// 0x11 Key N
	[6]u16 { 	k.L('o'), 	'O', 		k.A('o'), 	k.A('O'), 	k.A('O'), 	k.C('O') 	},	// 0x12 Key O
	[6]u16 { 	k.L('p'), 	'P', 		k.A('p'), 	k.A('P'), 	k.A('P'), 	k.C('P') 	},	// 0x13 Key P
	[6]u16 { 	k.L('q'), 	'Q', 		k.A('q'), 	k.A('Q'), 	k.A('Q'), 	k.C('Q') 	},	// 0x14 Key Q
	[6]u16 { 	k.L('r'), 	'R', 		k.A('r'), 	k.A('R'), 	k.A('R'), 	k.C('R') 	},	// 0x15 Key R
	[6]u16 { 	k.L('s'), 	'S', 		k.A('s'), 	k.A('S'), 	k.A('S'), 	k.C('S') 	},	// 0x16 Key S
	[6]u16 { 	k.L('t'), 	'T', 		k.A('t'), 	k.A('T'), 	k.A('T'), 	k.C('T') 	},	// 0x17 Key T
	[6]u16 { 	k.L('u'), 	'U', 		k.A('u'), 	k.A('U'), 	k.A('U'), 	k.C('U') 	},	// 0x18 Key U
	[6]u16 { 	k.L('v'), 	'V', 		k.A('v'), 	k.A('V'), 	k.A('V'), 	k.C('V') 	},	// 0x19 Key V
	[6]u16 { 	k.L('w'), 	'W', 		k.A('w'), 	k.A('W'), 	k.A('W'), 	k.C('W') 	},	// 0x1a Key W
	[6]u16 { 	k.L('x'), 	'X', 		k.A('x'), 	k.A('X'), 	k.A('X'), 	k.C('X') 	},	// 0x1b Key X
	[6]u16 { 	k.L('y'), 	'Y', 		k.A('y'), 	k.A('Y'), 	k.A('Y'), 	k.C('Y') 	},	// 0x1c Key Y
	[6]u16 { 	k.L('z'), 	'Z', 		k.A('z'), 	k.A('Z'), 	k.A('Z'), 	k.C('Z') 	},	// 0x1d Key Z
	[6]u16 {	'1', 		'!',		k.A('1'),	k.A('1'),	k.A('!'),	k.C('A')	},	// 0x1e Key 1
	[6]u16 {	'2', 		'@',		k.A('2'),	k.A('2'),	k.A('@'),	k.C('@')	},	// 0x1f Key 2
	[6]u16 {	'3', 		'#',		k.A('3'),	k.A('3'),	k.A('#'),	k.C('C')	},	// 0x20 Key 3
	[6]u16 {	'4', 		'$',		k.A('4'),	k.A('4'),	k.A('$'),	k.C('D')	},	// 0x21 Key 4
	[6]u16 {	'5', 		'%',		k.A('5'),	k.A('5'),	k.A('%'),	k.C('E')	},	// 0x22 Key 5
	[6]u16 {	'6', 		'^',		k.A('6'),	k.A('6'),	k.A('^'),	k.C('^')	},	// 0x23 Key 6
	[6]u16 {	'7', 		'&',		k.A('7'),	k.A('7'),	k.A('&'),	k.C('G')	},	// 0x24 Key 7
	[6]u16 {	'8', 		'*',		k.A('8'),	k.A('8'),	k.A('*'),	k.C('H')	},	// 0x25 Key 8
	[6]u16 {	'9', 		'(',		k.A('9'),	k.A('9'),	k.A('('),	k.C('I')	},	// 0x26 Key 9
	[6]u16 {	'0', 		')',		k.A('0'),	k.A('0'),	k.A(')'),	k.C('@')	},	// 0x27 Key 0
	[6]u16 { 	k.C('J'), 	k.C('J'), 	k.CA('J'), 	k.CA('J'), 	k.CA('J'), 	k.C('J')	},	// 0x28 Key ENTER
	[6]u16 {	k.C('['),	k.C('['),	k.CA('['),	k.CA('['),	k.CA('['),	k.C('[')	},	// 0x29 Key ESC
	[6]u16 {	k.C('H'),	k.C('H'),	k.CA('H'),	k.CA('H'),	k.CA('H'),	127			}, 	// 0x2a Key BACKSPACE
	[6]u16 {	k.C('I'),	k.C('I'),	k.CA('I'),	k.CA('I'),	k.CA('I'),	k.C('I')	},	// 0x2b Key TAB
	[6]u16 {	' ',		' ',		k.A(' '),	k.A(' '),	k.A(' '),	k.C('@')	},	// 0x2c Key SPACEBAR
	[6]u16 {	'-',		'_',		k.A('-'),	k.A('-'),	k.A('_'),	k.C('_')	},	// 0x2d Key DASH
	[6]u16 {	'=',		'+',		k.A('='),	k.A('='),	k.A('+'),	k.C('@')	},	// 0x2e Key EQUAL
	[6]u16 {	'[',		'{',		k.A('['),	k.A('['),	k.A('{'),	k.C('[')	},	// 0x2f Key OPEN_BRACKET
	[6]u16 {	']',		'}',		k.A(']'),	k.A(']'),	k.A('}'),	k.C(']')	},	// 0x30 Key CLOSE_BRACKET
	[6]u16 {	'\\',		'|',		k.A('\\'),	k.A('\\'),	k.A('|'),	k.C('\\')	},	// 0x31 Key BACKSLASH
	[6]u16 {	0, 			0, 			0, 			0, 			0, 			0			},	// 0x32 Key ??
	[6]u16 {	';',		':',		k.A(';'),	k.A(';'),	k.A(':'),	k.C('@')	},	// 0x33 Key SEMICOLON
	[6]u16 {	'\'',		'"',		k.A('\''),	k.A('\''),	k.A('"'),	k.C('@')	},	// 0x34 Key APOSTROPH
	[6]u16 {	'`',		'~',		k.A('`'),	k.A('`'),	k.A('~'),	k.C('@')	},	// 0x35 Key GRAVE_ACCENT
	[6]u16 {	',',		'<',		k.A(','),	k.A(','),	k.A('<'),	k.C('@')	},	// 0x36 Key COMMA
	[6]u16 {	'.',		'>',		k.A('.'),	k.A('.'),	k.A('>'),	k.C('@')	},	// 0x37 Key PERIOD
	[6]u16 {	'/',		'?',		k.A('/'),	k.A('/'),	k.A('?'),	k.C('@')	},	// 0x38 Key SLASH
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
	[6]u16 {	k.DEL,		k.DEL,		k.A(k.DEL),	k.A(k.DEL),	k.A(k.DEL),	k.DEL		},	// 0x4c Key DELETE
	[6]u16 {	k.END,		k.END,		k.AEND,		k.AEND,		k.AEND,		k.CEND		},	// 0x4d Key END
	[6]u16 {	k.PGDN,		k.PGDN,		k.APGDN,	k.APGDN,	k.APGDN,	k.CPGDN		},	// 0x4e Key PAGE_DOWN
	[6]u16 {	k.RIGHT,	k.RIGHT,	k.ARIGHT,	k.ARIGHT,	k.ARIGHT,	k.CRIGHT	},	// 0x4f Key RIGHT_ARROW
	[6]u16 {	k.LEFT,		k.LEFT,		k.ALEFT,	k.ALEFT,	k.ALEFT,	k.CLEFT		},	// 0x50 Key LEFT_ARROW
	[6]u16 {	k.DOWN,		k.DOWN,		k.ADOWN,	k.ADOWN,	k.ADOWN,	k.CDOWN		},	// 0x51 Key DOWN_ARROW
	[6]u16 {	k.UP,		k.UP,		k.AUP,		k.AUP,		k.AUP,		k.CUP		},	// 0x52 Key UP_ARROW
	[6]u16 {	k.NLOCK,	k.NLOCK,	k.NLOCK,	k.NLOCK,	k.NLOCK,	k.NLOCK		},	// 0x53 Key NUM_LOCK
	[6]u16 {	'/',		'/',		k.A('/'),	k.A('/'),	k.A('/'),	k.C('@')	},	// 0x54 Key KP_SLASH
	[6]u16 {	'*',		'*',		k.A('*'),	k.A('*'),	k.A('*'),	k.C('@')	},	// 0x55 Key KP_STAR
	[6]u16 {	'-',		'-',		k.AMIN,		k.AMIN,		k.A('-'),	k.CNMIN		},	// 0x56 Key KP_DASH
	[6]u16 {	'+',		'+',		k.APLUS,	k.APLUS,	k.A('+'),	k.CPLUS		},	// 0x57 Key KP_PLUS
	[6]u16 {	k.C('J'),	k.C('J'),	k.CA('J'),	k.CA('J'),	k.CA('J'),	k.C('J')	},	// 0x58 Key KP_ENTER
	[6]u16 {	k.NEND,		'1',		k.AEND,		k.AEND,		k.A('1'),	k.CEND		},	// 0x59 Key KP_1
	[6]u16 {	k.NDOWN,	'2',		k.ADOWN,	k.ADOWN,	k.A('2'),	k.CDOWN		},	// 0x5a Key KP_2
	[6]u16 {	k.NPGDN,	'3',		k.APGDN,	k.APGDN,	k.A('3'),	k.CPGDN		},	// 0x5b Key KP_3
	[6]u16 {	k.NLEFT,	'4',		k.ALEFT,	k.ALEFT,	k.A('4'),	k.CLEFT		},	// 0x5c Key KP_4
	[6]u16 {	k.NMID,		'5',		k.AMID,		k.AMID,		k.A('5'),	k.CMID		},	// 0x5d Key KP_5
	[6]u16 {	k.NRIGHT,	'6',		k.ARIGHT,	k.ARIGHT,	k.A('6'),	k.CRIGHT	},	// 0x5e Key KP_6
	[6]u16 {	k.NHOME,	'7',		k.AHOME,	k.AHOME,	k.A('7'),	k.CHOME		},	// 0x5f Key KP_7
	[6]u16 {	k.NUP,		'8',		k.AUP,		k.AUP,		k.A('8'),	k.CUP		},	// 0x60 Key KP_8
	[6]u16 {	k.NPGUP,	'9',		k.APGUP,	k.APGUP,	k.A('9'),	k.CPGUP		},	// 0x61 Key KP_9
	[6]u16 {	k.NINSRT,	'0',		k.AINSRT,	k.AINSRT,	k.A('0'),	k.CINSRT	},	// 0x62 Key KP_0
	[6]u16 {	k.NDEL,		'.',		k.A(k.DEL),	k.A(k.DEL),	k.A('.'),	k.DEL		},	// 0x63 Key KP_PERIOD
	[6]u16 {	'<',		'>',		k.A('<'),	k.A('|'),	k.A('>'),	k.C('@')	},	// 0x64 Key EUROPE_2
	[6]u16 {	k.C('M'),	k.C('M'),	k.CA('M'),	k.CA('M'),	k.CA('M'),	k.C('J')	}	// 0x65 Key APPLICATION
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
