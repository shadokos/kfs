/// AML stream skip helpers.
///
/// These functions advance the stream past AML constructs without creating
/// any namespace nodes. They are used during the loading phase (§5.4.2) to
/// skip over opcodes that are not relevant to namespace construction
/// (control flow, runtime expressions, etc.).
///
/// All skip functions are "best effort": if the stream ends prematurely,
/// they stop silently rather than returning an error. This mirrors the
/// recovery behaviour of parse_term_list.
const parser = @import("parser.zig");
const opcodes = @import("opcodes.zig");
const path_mod = @import("../namespace/path.zig");

const Stream = parser.Stream;

// ---------------------------------------------------------------------------
// PkgLength-based skip
// ---------------------------------------------------------------------------

/// Decode a PkgLength and skip past the entire body (§20.2.4).
pub fn skip_pkg_length(stream: *Stream) void {
    const pkg = parser.decode_pkg_length(stream) orelse return;
    stream.skip(pkg.body_length);
}

// ---------------------------------------------------------------------------
// String skip
// ---------------------------------------------------------------------------

/// Skip past a null-terminated AsciiString (§20.2.3 String).
pub fn skip_string(stream: *Stream) void {
    while (stream.pos < stream.data.len) {
        if (stream.data[stream.pos] == 0) {
            stream.pos += 1;
            return;
        }
        stream.pos += 1;
    }
}

// ---------------------------------------------------------------------------
// NamePath skip
// ---------------------------------------------------------------------------

/// Skip past a NamePath/NameString encoding (§20.2.2).
/// Handles RootChar, ParentPrefixChar, NullName, DualNamePath,
/// MultiNamePath, and single NameSeg.
pub fn skip_name_path(stream: *Stream) void {
    if (stream.pos >= stream.data.len) return;
    var pos = stream.pos;

    // RootChar (0x5C)
    if (pos < stream.data.len and stream.data[pos] == path_mod.ROOT_PREFIX) {
        pos += 1;
    }

    // ParentPrefixChar (0x5E), zero or more
    while (pos < stream.data.len and stream.data[pos] == path_mod.PARENT_PREFIX) {
        pos += 1;
    }

    if (pos >= stream.data.len) {
        stream.pos = pos;
        return;
    }

    const b = stream.data[pos];

    // NullName (0x00)
    if (b == path_mod.NULLNAME) {
        stream.pos = pos + 1;
        return;
    }

    // DualNamePath (0x2E + 2 NameSegs = 9 bytes)
    if (b == path_mod.DUAL_NAME_PREFIX) {
        pos += 1;
        if (pos + 8 <= stream.data.len) {
            stream.pos = pos + 8;
        } else {
            stream.pos = stream.data.len;
        }
        return;
    }

    // MultiNamePath (0x2F + count + count*4 bytes)
    if (b == path_mod.MULTI_NAME_PREFIX) {
        pos += 1;
        if (pos >= stream.data.len) {
            stream.pos = pos;
            return;
        }
        const count = stream.data[pos];
        pos += 1;
        const total = pos + @as(usize, count) * 4;
        stream.pos = @min(total, stream.data.len);
        return;
    }

    // Single NameSeg (4 bytes starting with a lead char)
    if (path_mod.is_name_lead(b)) {
        if (pos + 4 <= stream.data.len) {
            stream.pos = pos + 4;
        } else {
            stream.pos = stream.data.len;
        }
        return;
    }

    // Not a valid NamePath start, don't advance
    stream.pos = pos;
}

// ---------------------------------------------------------------------------
// TermArg skip (recursive)
// ---------------------------------------------------------------------------

/// Skip past a single TermArg (§20.2.5 TermArg).
/// This is recursive: expression opcodes (§20.2.5.4) contain nested TermArgs.
pub fn skip_term_arg(stream: *Stream) void {
    const op = stream.peek() orelse return;
    switch (op) {
        // Integer/string constants (§20.2.3)
        opcodes.ZERO_OP,
        opcodes.ONE_OP,
        opcodes.ONES_OP,
        => _ = stream.read_byte(),

        opcodes.BYTE_PREFIX => {
            _ = stream.read_byte();
            _ = stream.read_byte();
        },
        opcodes.WORD_PREFIX => {
            _ = stream.read_byte();
            _ = stream.read_word();
        },
        opcodes.DWORD_PREFIX => {
            _ = stream.read_byte();
            _ = stream.read_dword();
        },
        opcodes.QWORD_PREFIX => {
            _ = stream.read_byte();
            _ = stream.read_qword();
        },
        opcodes.STRING_PREFIX => {
            _ = stream.read_byte();
            skip_string(stream);
        },

        // PkgLength-delimited data objects (§20.2.3 DataObject, §20.2.5.4 DefBuffer)
        opcodes.BUFFER_OP,
        opcodes.PACKAGE_OP,
        opcodes.VAR_PACKAGE_OP,
        => {
            _ = stream.read_byte();
            skip_pkg_length(stream);
        },

        // Locals and Args (§20.2.6.2 LocalObj, §20.2.6.1 ArgObj)
        opcodes.LOCAL0...opcodes.LOCAL7,
        opcodes.ARG0...opcodes.ARG6,
        => _ = stream.read_byte(),

        // Arithmetic expression opcodes: 2 operands + Target (§20.2.5.4)
        opcodes.ADD_OP,
        opcodes.SUBTRACT_OP,
        opcodes.MULTIPLY_OP,
        opcodes.AND_OP,
        opcodes.NAND_OP,
        opcodes.OR_OP,
        opcodes.NOR_OP,
        opcodes.XOR_OP,
        opcodes.SHIFT_LEFT_OP,
        opcodes.SHIFT_RIGHT_OP,
        opcodes.MOD_OP,
        opcodes.CONCAT_OP,
        opcodes.CONCAT_RES_OP,
        => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_term_arg(stream);
            skip_target(stream);
        },

        // NOT: 1 operand + target
        opcodes.NOT_OP => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_target(stream);
        },

        // DIVIDE: 2 operands + 2 targets (remainder + quotient)
        opcodes.DIVIDE_OP => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_term_arg(stream);
            skip_target(stream);
            skip_target(stream);
        },

        // Increment/Decrement: SuperName
        opcodes.INCREMENT_OP, opcodes.DECREMENT_OP => {
            _ = stream.read_byte();
            skip_super_name(stream);
        },

        // Store: source + SuperName target
        opcodes.STORE_OP => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_super_name(stream);
        },

        // RefOf: SuperName
        opcodes.REF_OF_OP => {
            _ = stream.read_byte();
            skip_super_name(stream);
        },

        // Logical comparison: 2 operands (§20.2.5.4)
        opcodes.LEQUAL_OP,
        opcodes.LGREATER_OP,
        opcodes.LLESS_OP,
        opcodes.LAND_OP,
        opcodes.LOR_OP,
        => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_term_arg(stream);
        },

        // LNot: 1 operand
        opcodes.LNOT_OP => {
            _ = stream.read_byte();
            skip_term_arg(stream);
        },

        // DefMatch: SearchPkg MatchOpcode Operand MatchOpcode Operand StartIndex (§20.2.5.4)
        opcodes.MATCH_OP => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            _ = stream.read_byte();
            skip_term_arg(stream);
            _ = stream.read_byte();
            skip_term_arg(stream);
        },

        // Index: 2 operands + target
        opcodes.INDEX_OP => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_term_arg(stream);
            skip_target(stream);
        },

        // Unary: 1 operand
        opcodes.SIZE_OF_OP,
        opcodes.DEREF_OF_OP,
        opcodes.OBJECT_TYPE_OP,
        => {
            _ = stream.read_byte();
            skip_term_arg(stream);
        },

        // Conversion: 1 operand + target
        opcodes.TO_INTEGER_OP,
        opcodes.TO_BUFFER_OP,
        opcodes.TO_HEX_STRING_OP,
        opcodes.TO_DEC_STRING_OP,
        => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_target(stream);
        },

        // CopyObject: source + SuperName
        opcodes.COPY_OBJECT_OP => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_super_name(stream);
        },

        // Mid: 3 operands + target
        opcodes.MID_OP => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_term_arg(stream);
            skip_term_arg(stream);
            skip_target(stream);
        },

        // ToString: 2 operands + target
        opcodes.TO_STRING_OP => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_term_arg(stream);
            skip_target(stream);
        },

        // FindSetLeftBit/FindSetRightBit: 1 operand + target
        opcodes.FIND_SET_LEFT_BIT_OP,
        opcodes.FIND_SET_RIGHT_BIT_OP,
        => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_target(stream);
        },

        // Notify: SuperName + term arg
        opcodes.NOTIFY_OP => {
            _ = stream.read_byte();
            skip_super_name(stream);
            skip_term_arg(stream);
        },

        // CreateXxxField: 2 term args + name
        opcodes.CREATE_DWORD_FIELD_OP,
        opcodes.CREATE_WORD_FIELD_OP,
        opcodes.CREATE_BYTE_FIELD_OP,
        opcodes.CREATE_BIT_FIELD_OP,
        opcodes.CREATE_QWORD_FIELD_OP,
        => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_term_arg(stream);
            skip_name_path(stream);
        },

        // Control flow: PkgLength-delimited (§20.2.5.3)
        opcodes.IF_OP,
        opcodes.ELSE_OP,
        opcodes.WHILE_OP,
        => {
            _ = stream.read_byte();
            skip_pkg_length(stream);
        },

        // DefReturn: ArgObject (§20.2.5.3)
        opcodes.RETURN_OP => {
            _ = stream.read_byte();
            skip_term_arg(stream);
        },

        // Single-byte statement opcodes (§20.2.5.3)
        opcodes.BREAK_OP,
        opcodes.CONTINUE_OP,
        opcodes.NOOP_OP,
        opcodes.BREAK_POINT_OP,
        => _ = stream.read_byte(),

        // Scope/Method: PkgLength-delimited (§20.2.5.1, §20.2.5.2)
        opcodes.SCOPE_OP,
        opcodes.METHOD_OP,
        => {
            _ = stream.read_byte();
            skip_pkg_length(stream);
        },

        // DefName: NameString DataRefObject (§20.2.5.1)
        opcodes.NAME_OP => {
            _ = stream.read_byte();
            skip_name_path(stream);
            skip_term_arg(stream);
        },

        // DefAlias: NameString NameString (§20.2.5.1)
        opcodes.ALIAS_OP => {
            _ = stream.read_byte();
            skip_name_path(stream);
            skip_name_path(stream);
        },

        // DefExternal: NameString ObjectType ArgumentCount (§20.2.5.2)
        opcodes.EXTERNAL_OP => {
            _ = stream.read_byte();
            skip_name_path(stream);
            _ = stream.read_byte();
            _ = stream.read_byte();
        },

        // Extended prefix: delegate to skip_extended_term_arg
        opcodes.EXT_PREFIX => skip_extended_term_arg(stream),

        else => {
            if (path_mod.is_name_start(op)) {
                skip_name_path(stream);
            } else {
                _ = stream.read_byte();
            }
        },
    }
}

// ---------------------------------------------------------------------------
// Target / SuperName skip
// ---------------------------------------------------------------------------

/// Skip past a Target (§20.2.2: Target := SuperName | NullName).
pub fn skip_target(stream: *Stream) void {
    const b = stream.peek() orelse return;
    if (b == 0x00) {
        // NullTarget
        _ = stream.read_byte();
    } else {
        skip_super_name(stream);
    }
}

/// Skip past a SuperName (§20.2.2: SuperName := SimpleName | DebugObj | ReferenceTypeOpcode).
pub fn skip_super_name(stream: *Stream) void {
    const b = stream.peek() orelse return;
    if (b == opcodes.EXT_PREFIX) {
        _ = stream.read_byte();
        const ext = stream.peek() orelse return;
        if (ext == opcodes.EXT_DEBUG_OP) {
            _ = stream.read_byte();
            return;
        }
    }
    if (b == opcodes.DEREF_OF_OP) {
        _ = stream.read_byte();
        skip_term_arg(stream);
        return;
    }
    if (b == opcodes.REF_OF_OP) {
        _ = stream.read_byte();
        skip_term_arg(stream);
        return;
    }
    if (b == opcodes.INDEX_OP) {
        _ = stream.read_byte();
        skip_term_arg(stream);
        skip_term_arg(stream);
        skip_target(stream);
        return;
    }
    skip_name_path(stream);
}

// ---------------------------------------------------------------------------
// Extended opcode skip (inside skip_term_arg)
// ---------------------------------------------------------------------------

/// Skip an extended opcode term arg (EXT_PREFIX already peeked).
fn skip_extended_term_arg(stream: *Stream) void {
    _ = stream.read_byte(); // EXT_PREFIX
    const ext = stream.peek() orelse return;
    switch (ext) {
        // No-arg extended opcodes (§20.2.6.3 DebugOp, §20.2.3 RevisionOp, §20.2.5.4 TimerOp)
        opcodes.EXT_DEBUG_OP,
        opcodes.EXT_REVISION_OP,
        opcodes.EXT_TIMER_OP,
        => _ = stream.read_byte(),

        // DefDevice/DefProcessor/DefThermalZone/DefPowerRes/DefField/DefIndexField/DefBankField
        // All PkgLength-delimited (§20.2.5.2)
        opcodes.EXT_DEVICE_OP,
        opcodes.EXT_PROCESSOR_OP,
        opcodes.EXT_THERMAL_ZONE_OP,
        opcodes.EXT_POWER_RES_OP,
        opcodes.EXT_FIELD_OP,
        opcodes.EXT_INDEX_FIELD_OP,
        opcodes.EXT_BANK_FIELD_OP,
        => {
            _ = stream.read_byte();
            skip_pkg_length(stream);
        },

        // DefOpRegion: NameString RegionSpace RegionOffset RegionLen (no PkgLength, §20.2.5.2)
        opcodes.EXT_OP_REGION_OP => {
            _ = stream.read_byte();
            skip_name_path(stream);
            _ = stream.read_byte(); // RegionSpace
            skip_term_arg(stream); // RegionOffset
            skip_term_arg(stream); // RegionLen
        },

        // DefMutex: NameString SyncFlags (§20.2.5.2)
        opcodes.EXT_MUTEX_OP => {
            _ = stream.read_byte();
            skip_name_path(stream);
            _ = stream.read_byte(); // SyncFlags
        },

        // DefEvent: NameString (§20.2.5.2)
        opcodes.EXT_EVENT_OP => {
            _ = stream.read_byte();
            skip_name_path(stream);
        },

        // DefAcquire: MutexObject Timeout (§20.2.5.4)
        opcodes.EXT_ACQUIRE_OP => {
            _ = stream.read_byte();
            skip_super_name(stream);
            _ = stream.read_word(); // Timeout
        },

        // DefRelease/DefSignal/DefReset: SuperName/EventObject (§20.2.5.3)
        opcodes.EXT_RELEASE_OP,
        opcodes.EXT_SIGNAL_OP,
        opcodes.EXT_RESET_OP,
        => {
            _ = stream.read_byte();
            skip_super_name(stream);
        },

        // DefWait: EventObject Operand (§20.2.5.4)
        opcodes.EXT_WAIT_OP => {
            _ = stream.read_byte();
            skip_super_name(stream);
            skip_term_arg(stream);
        },

        // DefStall: UsecTime (§20.2.5.3) / DefSleep: MsecTime (§20.2.5.3)
        opcodes.EXT_STALL_OP,
        opcodes.EXT_SLEEP_OP,
        => {
            _ = stream.read_byte();
            skip_term_arg(stream);
        },

        // DefCondRefOf: SuperName Target (§20.2.5.4)
        opcodes.EXT_COND_REF_OF_OP => {
            _ = stream.read_byte();
            skip_super_name(stream);
            skip_target(stream);
        },

        // DefCreateField: SourceBuff BitIndex NumBits NameString (§20.2.5.2)
        opcodes.EXT_CREATE_FIELD_OP => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_term_arg(stream);
            skip_term_arg(stream);
            skip_name_path(stream);
        },

        // DefFatal: FatalType FatalCode FatalArg (§20.2.5.3)
        opcodes.EXT_FATAL_OP => {
            _ = stream.read_byte();
            _ = stream.read_byte();
            _ = stream.read_dword();
            skip_term_arg(stream);
        },

        // DefFromBCD/DefToBCD: Operand Target (§20.2.5.4)
        opcodes.EXT_FROM_BCD_OP,
        opcodes.EXT_TO_BCD_OP,
        => {
            _ = stream.read_byte();
            skip_term_arg(stream);
            skip_target(stream);
        },

        // DefDataRegion: NameString TermArg TermArg TermArg (§20.2.5.2)
        opcodes.EXT_DATA_REGION_OP => {
            _ = stream.read_byte();
            skip_name_path(stream);
            skip_term_arg(stream);
            skip_term_arg(stream);
            skip_term_arg(stream);
        },

        // DefLoad: NameString Target (§20.2.5.4 LoadOp ExtOpPrefix 0x20)
        opcodes.EXT_LOAD_OP => {
            _ = stream.read_byte();
            skip_name_path(stream);
            skip_super_name(stream);
        },

        // DefLoadTable: 6 TermArgs (§20.2.5.4 LoadTableOp ExtOpPrefix 0x1F)
        opcodes.EXT_LOAD_TABLE_OP => {
            _ = stream.read_byte();
            for (0..6) |_| skip_term_arg(stream);
        },

        else => {
            _ = stream.read_byte();
        },
    }
}

// ---------------------------------------------------------------------------
// Field PkgLength (used by field element parsing)
// ---------------------------------------------------------------------------

/// Decode a PkgLength used in field element lists (§20.2.5.2 NamedField).
/// Same encoding as PkgLength but the value is a bit count, not a byte count,
/// and we do not subtract the header size (it is the total bit width directly).
pub fn parse_field_pkg_length(stream: *Stream) u32 {
    const lead = stream.read_byte() orelse return 0;
    const follow_count: u2 = @truncate(lead >> 6);
    if (follow_count == 0) return lead & 0x3F;
    var length: u32 = lead & 0x0F;
    for (0..follow_count) |i| {
        const b = stream.read_byte() orelse return length;
        length |= @as(u32, b) << @intCast(4 + i * 8);
    }
    return length;
}
