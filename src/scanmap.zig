pub const scanmap_normal =
	[_]InputKey {
		InputKey.NONE,
		InputKey.ESCAPE,
		InputKey.ONE,
		InputKey.TWO,
		InputKey.THREE,
		InputKey.FOUR,
		InputKey.FIVE,
		InputKey.SIX,
		InputKey.SEVEN,
		InputKey.EIGHT,
		InputKey.NINE,
		InputKey.ZERO,
		InputKey.DASH,
		InputKey.EQUAL,
		InputKey.BACKSPACE,
		InputKey.TAB,
		InputKey.Q,
		InputKey.W,
		InputKey.E,
		InputKey.R,
		InputKey.T,
		InputKey.Y,
		InputKey.U,
		InputKey.I,
		InputKey.O,
		InputKey.P,
		InputKey.OPEN_BRACKET,
		InputKey.CLOSE_BRACKET,
		InputKey.ENTER,
		InputKey.LEFT_CTRL,
		InputKey.A,
		InputKey.S,
		InputKey.D,
		InputKey.F,
		InputKey.G,
		InputKey.H,
		InputKey.J,
		InputKey.K,
		InputKey.L,
		InputKey.SEMICOLON,
		InputKey.APOSTROPH,
		InputKey.GRAVE_ACCENT,
		InputKey.LEFT_SHIFT,
		InputKey.BACKSLASH,
		InputKey.Z,
		InputKey.X,
		InputKey.C,
		InputKey.V,
		InputKey.B,
		InputKey.N,
		InputKey.M,
		InputKey.COMMA,
		InputKey.PERIOD,
		InputKey.SLASH,
		InputKey.RIGHT_SHIFT,
		InputKey.KP_STAR,
		InputKey.LEFT_ALT,
		InputKey.SPACEBAR,
		InputKey.CAPS_LOCK,
		InputKey.F1,
		InputKey.F2,
		InputKey.F3,
		InputKey.F4,
		InputKey.F5,
		InputKey.F6,
		InputKey.F7,
		InputKey.F8,
		InputKey.F9,
		InputKey.F10,
		InputKey.NUM_LOCK,
		InputKey.SCROLL_LOCK,
		InputKey.KP_7,
		InputKey.KP_8,
		InputKey.KP_9,
		InputKey.KP_DASH,
		InputKey.KP_4,
		InputKey.KP_5,
		InputKey.KP_6,
		InputKey.KP_PLUS,
		InputKey.KP_1,
		InputKey.KP_2,
		InputKey.KP_3,
		InputKey.KP_0,
		InputKey.KP_PERIOD,
		InputKey.SYSREQ,
		InputKey.NONE,
		InputKey.EUROPE_2,
		InputKey.F11,
		InputKey.F12,
		InputKey.KP_EQUAL,
		InputKey.NONE,
		InputKey.NONE,
		InputKey.I10L_6,
	}
	++
	([_]InputKey {
		InputKey.NONE,
	} ** 7)
	++
	[_]InputKey {
		InputKey.F13,
		InputKey.F14,
		InputKey.F15,
		InputKey.F16,
		InputKey.F17,
		InputKey.F18,
		InputKey.F19,
		InputKey.F20,
		InputKey.F21,
		InputKey.F22,
		InputKey.F23,
		InputKey.NONE,
		InputKey.I10L_2,
	}
	++
	([_]InputKey { InputKey.NONE, } ** 13)
	++
	[_]InputKey {
		InputKey.EQUAL_SIGN
	};

pub const scanmap_special =
	([_]InputKey {
		InputKey.NONE,
	} ** 28)
	++
	[_]InputKey {
		InputKey.KP_ENTER, // 0x1c
		InputKey.RIGHT_CTRL,
	}
	++
	([_]InputKey {
		InputKey.NONE,
	} ** 23)
	++
	([_]InputKey {
		InputKey.KP_SLASH,
		InputKey.NONE,
		InputKey.PRINT_SCREEN,
		InputKey.RIGHT_ALT,
	})
	++
	([_]InputKey {
		InputKey.NONE,
	} ** 13)
	++
	([_]InputKey {
		InputKey.PAUSE,
		InputKey.HOME,
		InputKey.UP_ARROW,
		InputKey.PAGE_UP,
		InputKey.NONE,
		InputKey.LEFT_ARROW,
		InputKey.NONE,
		InputKey.RIGHT_ARROW,
		InputKey.NONE,
		InputKey.END,
		InputKey.DOWN_ARROW,
		InputKey.PAGE_DOWN,
		InputKey.INSERT,
		InputKey.DELETE,
	})
	++
	([_]InputKey {
		InputKey.NONE,
	} ** 7)
	++
	[_]InputKey {
		InputKey.LEFT_GUI,
		InputKey.RIGHT_GUI,
		InputKey.APPLICATION,
	}
;

pub const InputKey =  enum(u16) {
	NONE = 0x0000,
	A = 0x0004,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,
	ONE,
	TWO,
	THREE,
	FOUR,
	FIVE,
	SIX,
	SEVEN,
	EIGHT,
	NINE,
	ZERO,

	ENTER,
	ESCAPE,
	BACKSPACE,
	TAB,
	SPACEBAR,
	DASH,
	EQUAL,
	OPEN_BRACKET,
	CLOSE_BRACKET,
	BACKSLASH,
	EUROPE_1,
	SEMICOLON,
	APOSTROPH,
	GRAVE_ACCENT,
	COMMA,
	PERIOD,
	SLASH,
	CAPS_LOCK,

	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,

	PRINT_SCREEN,
	SCROLL_LOCK,
	PAUSE,
	INSERT,
	HOME,
	PAGE_UP,
	DELETE,
	END,
	PAGE_DOWN,
	RIGHT_ARROW,
	LEFT_ARROW,
	DOWN_ARROW,
	UP_ARROW,
	NUM_LOCK,

	KP_SLASH,
	KP_STAR,
	KP_DASH,
	KP_PLUS,
	KP_ENTER,
	KP_1,
	KP_2,
	KP_3,
	KP_4,
	KP_5,
	KP_6,
	KP_7,
	KP_8,
	KP_9,
	KP_0,
	KP_PERIOD,

	EUROPE_2,
	APPLICATION,
	POWER,
	KP_EQUAL,

	F13,
	F14,
	F15,
	F16,
	F17,
	F18,
	F19,
	F20,
	F21,
	F22,
	F23,
	F24,

	EXECUTE,
	HELP,
	MENU,
	SELECT,
	STOP,
	AGAIN,
	UNDO,
	CUT,
	COPY,
	PASTE,
	FIND,
	MUTE,
	VOLUME_UP,
	VOLUME_DOWN,
	LOCKING_CAPS_LOCK,
	LOCKING_NUM_LOCK,
	LOCKING_SCROLL_LOCK,
	KP_COMMA,
	EQUAL_SIGN,
	I10L_1,
	I10L_2,
	I10L_3,
	I10L_4,
	I10L_5,
	I10L_6,
	I10L_7,
	I10L_8,
	I10L_9,
	LANG_1,
	LANG_2,
	LANG_3,
	LANG_4,
	LANG_5,
	LANG_6,
	LANG_7,
	LANG_8,
	LANG_9,
	ALT_ERASE,
	SYSREQ,
	CANCEL,
	CLEAR,
	PRIOR,
	RETURN,
	SEPARATOR,
	OUT,
	OPER,
	CLEAR_AGAIN,
	CR_SEL,
	EX_SEL,

	// 0x00A5 -- 0x00AF RESERVED */

	KP_00 = 0x00B0,
	KP_000,
	THOUSANDS_SEP,
	DECIMAL_SEP,
	CURRENCY_UNIT,
	CURRENCY_SUBUNIT,
	KP_OPEN_PARENTHESIS,
	KP_CLOSE_PARENTHESIS,
	KP_OPEN_BRACE,
	KP_CLOSE_BRACE,
	KP_TAB,
	KP_BACKSPACE,
	KP_A,
	KP_B,
	KP_C,
	KP_D,
	KP_E,
	KP_F,
	KP_XOR,
	KP_CARET,
	KP_PERCENT,
	KP_SMALLER_THEN,
	KP_GREATER_THEN,
	KP_AMP,
	KP_DOUBLE_AMP,
	KP_PIPE,
	KP_DOUBLE_PIPE,
	KP_COLON,
	KP_NUMBER,
	KP_SPACE,
	KP_AT,
	KP_EXCLAMATION_MARK,
	KP_MEM_STORE,
	KP_MEM_RECALL,
	KP_MEM_CLEAR,
	KP_MEM_ADD,
	KP_MEM_SUBTRACT,
	KP_MEM_MULTIPLY,
	KP_MEM_DIVIDE,
	KP_PLUS_MINUS,
	KP_CLEAR,
	KP_CLEAR_ENTRY,
	KP_BIN,
	KP_OCT,
	KP_DEC,
	KP_HEX,

	// 0x00DE, 0x00DF RESERVED

	LEFT_CTRL = 0x00E0,
	LEFT_SHIFT,
	LEFT_ALT,
	LEFT_GUI,
	RIGHT_CTRL,
	RIGHT_SHIFT,
	RIGHT_ALT,
	RIGHT_GUI

	// 0x00E8 -- 0xFFFF RESERVED
};