/// AML opcode byte values (ACPI 6.4 §20.2, full table at §20.3 Table 20.2).
///
/// Single-byte opcodes are their literal byte value.
/// Extended (2-byte) opcodes are preceded by EXT_PREFIX (0x5B);
/// the constants below are the second byte only.

// -- Data object encodings (§20.2.3) --
pub const ZERO_OP: u8 = 0x00;
pub const ONE_OP: u8 = 0x01;
pub const BYTE_PREFIX: u8 = 0x0A;
pub const WORD_PREFIX: u8 = 0x0B;
pub const DWORD_PREFIX: u8 = 0x0C;
pub const STRING_PREFIX: u8 = 0x0D;
pub const QWORD_PREFIX: u8 = 0x0E;
pub const ONES_OP: u8 = 0xFF;

// -- Namespace modifier objects (§20.2.5.1) --
pub const ALIAS_OP: u8 = 0x06;
pub const NAME_OP: u8 = 0x08;
pub const SCOPE_OP: u8 = 0x10;

// -- Expression opcodes that create named objects (§20.2.5.4) --
pub const BUFFER_OP: u8 = 0x11;
pub const PACKAGE_OP: u8 = 0x12;
pub const VAR_PACKAGE_OP: u8 = 0x13;

// -- Named objects (§20.2.5.2) --
pub const METHOD_OP: u8 = 0x14;
pub const EXTERNAL_OP: u8 = 0x15;

// -- Name path encodings (§20.2.2) --
pub const DUAL_NAME_PREFIX: u8 = 0x2E;
pub const MULTI_NAME_PREFIX: u8 = 0x2F;
pub const ROOT_PREFIX: u8 = 0x5C; // '\'
pub const PARENT_PREFIX: u8 = 0x5E; // '^'

// -- Extended opcode prefix (§20.2.3 ExtOpPrefix = 0x5B) --
pub const EXT_PREFIX: u8 = 0x5B;

// -- Local and Arg operands (§20.2.6.2 LocalObj, §20.2.6.1 ArgObj) --
// Local0..Local7 = 0x60..0x67 (§20.2.6.2), Arg0..Arg6 = 0x68..0x6E (§20.2.6.1)
pub const LOCAL0: u8 = 0x60;
pub const LOCAL7: u8 = 0x67;
pub const ARG0: u8 = 0x68;
pub const ARG6: u8 = 0x6E;

// -- Expression opcodes: arithmetic, store, ref (§20.2.5.4) --
pub const STORE_OP: u8 = 0x70;
pub const REF_OF_OP: u8 = 0x71;
pub const ADD_OP: u8 = 0x72;
pub const CONCAT_OP: u8 = 0x73;
pub const SUBTRACT_OP: u8 = 0x74;
pub const INCREMENT_OP: u8 = 0x75;
pub const DECREMENT_OP: u8 = 0x76;
pub const MULTIPLY_OP: u8 = 0x77;
pub const DIVIDE_OP: u8 = 0x78;
pub const SHIFT_LEFT_OP: u8 = 0x79;
pub const SHIFT_RIGHT_OP: u8 = 0x7A;
pub const AND_OP: u8 = 0x7B;
pub const NAND_OP: u8 = 0x7C;
pub const OR_OP: u8 = 0x7D;
pub const NOR_OP: u8 = 0x7E;
pub const XOR_OP: u8 = 0x7F;
pub const NOT_OP: u8 = 0x80;
pub const FIND_SET_LEFT_BIT_OP: u8 = 0x81;
pub const FIND_SET_RIGHT_BIT_OP: u8 = 0x82;
pub const DEREF_OF_OP: u8 = 0x83;
pub const CONCAT_RES_OP: u8 = 0x84;
pub const MOD_OP: u8 = 0x85;
pub const NOTIFY_OP: u8 = 0x86;
pub const SIZE_OF_OP: u8 = 0x87;
pub const INDEX_OP: u8 = 0x88;
pub const MATCH_OP: u8 = 0x89; // DefMatch := MatchOp SearchPkg MatchOpcode Op MatchOpcode Op StartIndex
pub const CREATE_DWORD_FIELD_OP: u8 = 0x8A;
pub const CREATE_WORD_FIELD_OP: u8 = 0x8B;
pub const CREATE_BYTE_FIELD_OP: u8 = 0x8C;
pub const CREATE_BIT_FIELD_OP: u8 = 0x8D;
pub const OBJECT_TYPE_OP: u8 = 0x8E;
pub const CREATE_QWORD_FIELD_OP: u8 = 0x8F;

// -- Logical expression opcodes (§20.2.5.4) --
pub const LAND_OP: u8 = 0x90;
pub const LOR_OP: u8 = 0x91;
pub const LNOT_OP: u8 = 0x92;
pub const LEQUAL_OP: u8 = 0x93;
pub const LGREATER_OP: u8 = 0x94;
pub const LLESS_OP: u8 = 0x95;
// Note: LGreaterEqualOp, LLessEqualOp, LNotEqualOp are not standalone opcodes;
// they are decoded as LNOT_OP followed by LLESS_OP, LGREATER_OP, or LEQUAL_OP (§20.2.5.4).

// -- Type conversion opcodes (§20.2.5.4) --
pub const TO_BUFFER_OP: u8 = 0x96;
pub const TO_DEC_STRING_OP: u8 = 0x97;
pub const TO_HEX_STRING_OP: u8 = 0x98;
pub const TO_INTEGER_OP: u8 = 0x99;
// 0x9A-0x9B: reserved
pub const TO_STRING_OP: u8 = 0x9C;
pub const COPY_OBJECT_OP: u8 = 0x9D;
pub const MID_OP: u8 = 0x9E;

// -- Statement (control flow) opcodes (§20.2.5.3) --
pub const CONTINUE_OP: u8 = 0x9F;
pub const IF_OP: u8 = 0xA0;
pub const ELSE_OP: u8 = 0xA1;
pub const WHILE_OP: u8 = 0xA2;
pub const NOOP_OP: u8 = 0xA3;
pub const RETURN_OP: u8 = 0xA4;
pub const BREAK_OP: u8 = 0xA5;
// 0xA6-0xCB: reserved
pub const BREAK_POINT_OP: u8 = 0xCC;
// 0xCD-0xFE: reserved

// ============================================================
// Extended opcodes (preceded by EXT_PREFIX 0x5B)
// Second byte values listed below (§20.3 Table 20.2)
// ============================================================

// -- Named object extended opcodes (§20.2.5.2) --
pub const EXT_MUTEX_OP: u8 = 0x01;
pub const EXT_EVENT_OP: u8 = 0x02;
pub const EXT_COND_REF_OF_OP: u8 = 0x12;
pub const EXT_CREATE_FIELD_OP: u8 = 0x13;

// -- Table management extended opcodes (§20.2.5.4 LoadOp/LoadTableOp) --
pub const EXT_LOAD_TABLE_OP: u8 = 0x1F;
pub const EXT_LOAD_OP: u8 = 0x20;

// -- Synchronization extended opcodes: acquire/wait (§20.2.5.4), release/signal/reset (§20.2.5.3) --
pub const EXT_STALL_OP: u8 = 0x21;
pub const EXT_SLEEP_OP: u8 = 0x22;
pub const EXT_ACQUIRE_OP: u8 = 0x23;
pub const EXT_SIGNAL_OP: u8 = 0x24;
pub const EXT_WAIT_OP: u8 = 0x25;
pub const EXT_RESET_OP: u8 = 0x26;
pub const EXT_RELEASE_OP: u8 = 0x27;

// -- BCD conversion extended opcodes (§20.2.5.4) --
pub const EXT_FROM_BCD_OP: u8 = 0x28;
pub const EXT_TO_BCD_OP: u8 = 0x29;
// 0x2A-0x2F: reserved

// -- Misc extended opcodes (§20.2.5.3 FatalOp, §20.2.3 RevisionOp, §20.2.6.3 DebugOp, §20.2.5.4 TimerOp) --
pub const EXT_REVISION_OP: u8 = 0x30;
pub const EXT_DEBUG_OP: u8 = 0x31;
pub const EXT_FATAL_OP: u8 = 0x32;
pub const EXT_TIMER_OP: u8 = 0x33;

// -- Named region/field extended opcodes (§20.2.5.2) --
pub const EXT_OP_REGION_OP: u8 = 0x80;
pub const EXT_FIELD_OP: u8 = 0x81;
pub const EXT_DEVICE_OP: u8 = 0x82;
/// DefProcessor: permanently reserved in ACPI 6.4 (§20.3 Table 20.2).
/// May still appear in legacy DSDT/SSDT tables; parse but do not generate.
pub const EXT_PROCESSOR_OP: u8 = 0x83;
pub const EXT_POWER_RES_OP: u8 = 0x84;
pub const EXT_THERMAL_ZONE_OP: u8 = 0x85;
pub const EXT_INDEX_FIELD_OP: u8 = 0x86;
pub const EXT_BANK_FIELD_OP: u8 = 0x87;
pub const EXT_DATA_REGION_OP: u8 = 0x88;
