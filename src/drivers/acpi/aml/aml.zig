/// AML table loader: parses DSDT/SSDT bytecode and populates the namespace.
///
/// Loads named objects (Name, Device, Scope, Method, OpRegion,
/// Field, Processor, ThermalZone, PowerResource, Mutex) into the
/// namespace tree. Methods are NOT executed during loading, only their
/// bytecode range is recorded for later evaluation.
///
/// Opcode handling is modular: each opcode has a dedicated handler in
/// the handlers/ directory. Dispatch is resolved at comptime via
/// handlers.zig (no runtime table, no build step).
const std = @import("std");
const parser = @import("parser.zig");
const opcodes = @import("opcodes.zig");
const handlers = @import("handlers.zig");
const skip = @import("skip.zig");
const path_mod = @import("../namespace/path.zig");
const ns_mod = @import("../namespace/namespace.zig");
const node_mod = @import("../namespace/node.zig");
const osl = @import("../os_layer.zig");

const Namespace = ns_mod.Namespace;
const Node = node_mod.Node;
const Stream = parser.Stream;
const Error = handlers.Error;

const log = std.log.scoped(.acpi_aml);

// ---------------------------------------------------------------------------
// Loading statistics
// ---------------------------------------------------------------------------

var stats = Stats{};

const Stats = struct {
    names: u32 = 0,
    methods: u32 = 0,
    devices: u32 = 0,
    scopes: u32 = 0,
    op_regions: u32 = 0,
    fields: u32 = 0,
    processors: u32 = 0,
    thermal_zones: u32 = 0,
    power_resources: u32 = 0,
    mutexes: u32 = 0,
    skipped: u32 = 0,
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Load an AML table (DSDT or SSDT data) into the namespace.
pub fn load_table(
    ns: *Namespace,
    aml_data: []const u8,
) Error!void {
    var stream = Stream{ .data = aml_data };
    stats = .{};

    log.debug("Loading AML table: {d} bytes", .{aml_data.len});

    parse_term_list_entry(ns, ns.root, &stream);

    log.info(
        "Loaded: {d} names, {d} methods, {d} devices, " ++
            "{d} scopes, {d} regions, {d} fields, {d} skipped",
        .{
            stats.names,      stats.methods,
            stats.devices,    stats.scopes,
            stats.op_regions, stats.fields,
            stats.skipped,
        },
    );
}

// ---------------------------------------------------------------------------
// Term list / term parsing
// ---------------------------------------------------------------------------

/// Entry point for parse_term_list, callable as a function pointer.
/// This is the function stored in HandleContext.parse_term_list to allow
/// handlers to recurse without circular imports.
fn parse_term_list_entry(ns: *Namespace, scope: *Node, stream: *Stream) void {
    parse_term_list(ns, scope, stream);
}

/// Parse a list of AML terms until stream is exhausted (§20.2.5).
fn parse_term_list(
    ns: *Namespace,
    scope: *Node,
    stream: *Stream,
) void {
    while (!stream.eof()) {
        const before_pos = stream.pos;
        const op_byte = stream.peek() orelse break;
        parse_term(ns, scope, stream) catch |err| {
            switch (err) {
                Error.parse_error => {
                    if (op_byte == opcodes.EXT_PREFIX) {
                        const ext_byte = if (before_pos + 1 < stream.data.len)
                            stream.data[before_pos + 1]
                        else
                            0;
                        log.warn(
                            "SKIP: unknown ext opcode 0x5B{x:0>2} at offset 0x{x}",
                            .{ ext_byte, before_pos },
                        );
                    } else {
                        log.warn(
                            "SKIP: unknown opcode 0x{x:0>2} at offset 0x{x}",
                            .{ op_byte, before_pos },
                        );
                    }
                    _ = stream.read_byte();
                    stats.skipped += 1;
                },
                else => {
                    log.err(
                        "AML error at offset 0x{x}: {s}",
                        .{ stream.pos, @errorName(err) },
                    );
                    return;
                },
            }
        };
        // Safety: if we didn't advance, force skip to avoid infinite loop
        if (stream.pos == before_pos) {
            log.warn("STUCK: no progress at offset 0x{x}, opcode 0x{x:0>2}, forcing skip", .{
                before_pos, op_byte,
            });
            _ = stream.read_byte();
            stats.skipped += 1;
        }
    }
}

/// Parse a single AML term (§20.2.5).
fn parse_term(
    ns: *Namespace,
    scope: *Node,
    stream: *Stream,
) Error!void {
    const op = stream.peek() orelse return;
    const alloc = osl.allocator();

    const ctx = handlers.HandleContext{
        .ns = ns,
        .scope = scope,
        .stream = stream,
        .alloc = alloc,
        .parse_term_list = &parse_term_list_entry,
    };

    // Extended opcodes (EXT_PREFIX 0x5B + second byte)
    if (op == opcodes.EXT_PREFIX) {
        _ = stream.read_byte(); // EXT_PREFIX
        const ext_op = stream.read_byte() orelse return Error.parse_error;

        if (try handlers.dispatch_ext(ext_op, ctx)) {
            return;
        }

        // No handler: skip the extended opcode body
        skip_extended_body(ext_op, stream);
        return;
    }

    // Simple opcodes: try dispatch first
    if (try handlers.dispatch(op, ctx)) {
        return;
    }

    // No handler: skip the opcode
    skip_simple_body(op, stream);
}

// ---------------------------------------------------------------------------
// Skip logic for unhandled opcodes
// ---------------------------------------------------------------------------

/// Skip the body of a simple (non-extended) opcode that has no handler.
fn skip_simple_body(op: u8, stream: *Stream) void {
    switch (op) {
        // Single-byte no-arg opcodes (§20.2.5.3, §20.2.5.4, §20.2.6.1, §20.2.6.2)
        opcodes.ZERO_OP,
        opcodes.ONE_OP,
        opcodes.ONES_OP,
        opcodes.NOOP_OP,
        opcodes.BREAK_OP,
        opcodes.CONTINUE_OP,
        opcodes.BREAK_POINT_OP,
        opcodes.LOCAL0...opcodes.LOCAL7,
        opcodes.ARG0...opcodes.ARG6,
        => _ = stream.read_byte(),

        // Literal constants with fixed payload (§20.2.3)
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
            skip.skip_string(stream);
        },

        // PkgLength-delimited blocks (§20.2.5.4 DefBuffer, §20.2.5.3 DefWhile/DefIf/DefElse)
        opcodes.BUFFER_OP,
        opcodes.PACKAGE_OP,
        opcodes.VAR_PACKAGE_OP,
        opcodes.IF_OP,
        opcodes.ELSE_OP,
        opcodes.WHILE_OP,
        => {
            _ = stream.read_byte();
            skip.skip_pkg_length(stream);
        },

        // DefReturn: ArgObject (§20.2.5.3)
        opcodes.RETURN_OP => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
        },

        // DefStore: TermArg SuperName (§20.2.5.4)
        opcodes.STORE_OP => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            skip.skip_super_name(stream);
        },

        // Arithmetic: 2 Operands + Target (§20.2.5.4)
        opcodes.ADD_OP,
        opcodes.SUBTRACT_OP,
        opcodes.MULTIPLY_OP,
        opcodes.AND_OP,
        opcodes.OR_OP,
        opcodes.XOR_OP,
        opcodes.SHIFT_LEFT_OP,
        opcodes.SHIFT_RIGHT_OP,
        opcodes.NAND_OP,
        opcodes.NOR_OP,
        opcodes.MOD_OP,
        opcodes.CONCAT_OP,
        opcodes.CONCAT_RES_OP,
        => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            skip.skip_term_arg(stream);
            skip.skip_target(stream);
        },

        // DefNot: Operand Target (§20.2.5.4)
        opcodes.NOT_OP => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            skip.skip_target(stream);
        },

        // DefDivide: Dividend Divisor Remainder Quotient (§20.2.5.4)
        opcodes.DIVIDE_OP => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            skip.skip_term_arg(stream);
            skip.skip_target(stream);
            skip.skip_target(stream);
        },

        // DefIncrement/DefDecrement: SuperName (§20.2.5.4)
        opcodes.INCREMENT_OP, opcodes.DECREMENT_OP => {
            _ = stream.read_byte();
            skip.skip_super_name(stream);
        },

        // Logical comparisons: 2 Operands (§20.2.5.4)
        opcodes.LEQUAL_OP,
        opcodes.LGREATER_OP,
        opcodes.LLESS_OP,
        opcodes.LAND_OP,
        opcodes.LOR_OP,
        => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            skip.skip_term_arg(stream);
        },
        opcodes.LNOT_OP => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
        },

        // DefMatch: SearchPkg MatchOpcode Operand MatchOpcode Operand StartIndex (§20.2.5.4)
        opcodes.MATCH_OP => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
        },

        // Collection ops (§20.2.5.4)
        opcodes.INDEX_OP => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            skip.skip_term_arg(stream);
            skip.skip_target(stream);
        },
        opcodes.SIZE_OF_OP,
        opcodes.DEREF_OF_OP,
        opcodes.REF_OF_OP,
        opcodes.OBJECT_TYPE_OP,
        => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
        },
        opcodes.COPY_OBJECT_OP => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            skip.skip_super_name(stream);
        },

        // DefMid: MidObj TermArg TermArg Target (§20.2.5.4)
        opcodes.MID_OP => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            skip.skip_term_arg(stream);
            skip.skip_term_arg(stream);
            skip.skip_target(stream);
        },

        // DefToString: TermArg LengthArg Target (§20.2.5.4)
        opcodes.TO_STRING_OP => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            skip.skip_term_arg(stream);
            skip.skip_target(stream);
        },

        // Type conversions: Operand Target (§20.2.5.4)
        opcodes.TO_INTEGER_OP,
        opcodes.TO_BUFFER_OP,
        opcodes.TO_HEX_STRING_OP,
        opcodes.TO_DEC_STRING_OP,
        opcodes.FIND_SET_LEFT_BIT_OP,
        opcodes.FIND_SET_RIGHT_BIT_OP,
        => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            skip.skip_target(stream);
        },

        // DefNotify: NotifyObject NotifyValue (§20.2.5.3)
        opcodes.NOTIFY_OP => {
            _ = stream.read_byte();
            skip.skip_super_name(stream);
            skip.skip_term_arg(stream);
        },

        // DefCreateXxxField: SourceBuff ByteIndex NameString (§20.2.5.2)
        opcodes.CREATE_DWORD_FIELD_OP,
        opcodes.CREATE_WORD_FIELD_OP,
        opcodes.CREATE_BYTE_FIELD_OP,
        opcodes.CREATE_BIT_FIELD_OP,
        opcodes.CREATE_QWORD_FIELD_OP,
        => {
            _ = stream.read_byte();
            skip.skip_term_arg(stream);
            skip.skip_term_arg(stream);
            skip.skip_name_path(stream);
        },

        // DefAlias: NameString NameString (§20.2.5.1)
        opcodes.ALIAS_OP => {
            _ = stream.read_byte();
            skip.skip_name_path(stream);
            skip.skip_name_path(stream);
        },

        else => {
            // NamePath (method call at scope level)
            if (path_mod.is_name_start(op)) {
                skip.skip_name_path(stream);
            } else {
                // Unknown: will be caught by the stuck check in parse_term_list
                _ = stream.read_byte();
                stats.skipped += 1;
            }
        },
    }
}

/// Skip the body of an extended opcode (EXT_PREFIX and ext_op already consumed).
fn skip_extended_body(ext_op: u8, stream: *Stream) void {
    switch (ext_op) {
        // PkgLength-delimited named object blocks (§20.2.5.2)
        opcodes.EXT_BANK_FIELD_OP,
        => skip.skip_pkg_length(stream),

        // DefEvent: NameString (§20.2.5.2)
        opcodes.EXT_EVENT_OP => skip.skip_name_path(stream),

        // DefCreateField: SourceBuff BitIndex NumBits NameString (§20.2.5.2)
        opcodes.EXT_CREATE_FIELD_OP => {
            skip.skip_term_arg(stream);
            skip.skip_term_arg(stream);
            skip.skip_term_arg(stream);
            skip.skip_name_path(stream);
        },

        // DefAcquire: MutexObject Timeout (§20.2.5.4)
        opcodes.EXT_ACQUIRE_OP => {
            skip.skip_super_name(stream);
            _ = stream.read_word();
        },

        // DefRelease/DefSignal/DefReset: SuperName (§20.2.5.3)
        opcodes.EXT_RELEASE_OP,
        opcodes.EXT_SIGNAL_OP,
        opcodes.EXT_RESET_OP,
        => skip.skip_super_name(stream),

        // DefWait: EventObject Operand (§20.2.5.4)
        opcodes.EXT_WAIT_OP => {
            skip.skip_super_name(stream);
            skip.skip_term_arg(stream);
        },

        // DefStall/DefSleep: UsecTime/MsecTime (§20.2.5.3)
        opcodes.EXT_STALL_OP, opcodes.EXT_SLEEP_OP => skip.skip_term_arg(stream),

        // DefCondRefOf: SuperName Target (§20.2.5.4)
        opcodes.EXT_COND_REF_OF_OP => {
            skip.skip_super_name(stream);
            skip.skip_target(stream);
        },

        // DefFatal: FatalType FatalCode FatalArg (§20.2.5.3)
        opcodes.EXT_FATAL_OP => {
            _ = stream.read_byte();
            _ = stream.read_dword();
            skip.skip_term_arg(stream);
        },

        // DefFromBCD/DefToBCD: Operand Target (§20.2.5.4)
        opcodes.EXT_FROM_BCD_OP,
        opcodes.EXT_TO_BCD_OP,
        => {
            skip.skip_term_arg(stream);
            skip.skip_target(stream);
        },

        // DefDataRegion: NameString TermArg TermArg TermArg (§20.2.5.2)
        opcodes.EXT_DATA_REGION_OP => {
            skip.skip_name_path(stream);
            skip.skip_term_arg(stream);
            skip.skip_term_arg(stream);
            skip.skip_term_arg(stream);
        },

        // DefLoad: NameString Target (§20.2.5.4 via LoadOp ExtOpPrefix 0x20)
        opcodes.EXT_LOAD_OP => {
            skip.skip_name_path(stream);
            skip.skip_super_name(stream);
        },

        // DefLoadTable: 6 TermArgs (§20.2.5.4 via LoadTableOp ExtOpPrefix 0x1F)
        opcodes.EXT_LOAD_TABLE_OP => {
            for (0..6) |_| skip.skip_term_arg(stream);
        },

        // Zero-length extended opcodes (§20.2.6.3 DebugObj, §20.2.3 RevisionOp, §20.2.5.4 TimerOp)
        opcodes.EXT_DEBUG_OP,
        opcodes.EXT_REVISION_OP,
        opcodes.EXT_TIMER_OP,
        => {},

        else => {
            stats.skipped += 1;
        },
    }
}
