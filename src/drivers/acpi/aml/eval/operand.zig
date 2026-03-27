/// AML operand (expression-level) evaluation dispatcher (ACPI 6.4 §20.2.5.4).
///
/// Evaluates a single TermArg and returns its Object value.
/// Called wherever the grammar requires "TermArg => <Type>".
///
/// This is the expression-level counterpart to term.zig's statement-level
/// eval_term(). The split mirrors the AML grammar distinction between
/// TermObj (statements, §20.2.5) and ExpressionOpcode (values, §20.2.5.4).
const opcodes = @import("../opcodes.zig");
const objects = @import("../objects.zig");
const path_mod = @import("../../namespace/path.zig");
const skip = @import("../skip.zig");

const integer = @import("integer.zig");
const local_arg = @import("local_arg.zig");
const string = @import("string.zig");
const arithmetic = @import("arithmetic.zig");
const logical = @import("logical.zig");
const store = @import("store.zig");
const buffer = @import("buffer.zig");
const package_mod = @import("package.zig");
const ref = @import("ref.zig");
const misc = @import("misc.zig");
const convert = @import("convert.zig");
const method_inv = @import("method_inv.zig");

const Object = objects.Object;
const Error = @import("executor.zig").Error;
const EvalContext = @import("executor.zig").EvalContext;

/// Evaluate a single operand (TermArg) from the stream and return its value.
pub fn eval_operand(ectx: *EvalContext) Error!Object {
    const op = ectx.stream.peek() orelse return .uninitialized;
    const frame = ectx.ctx.current() orelse return .uninitialized;

    switch (op) {
        // -- Integer constants (§20.2.3) --
        opcodes.ZERO_OP => {
            _ = ectx.stream.read_byte();
            return .{ .integer = 0 };
        },
        opcodes.ONE_OP => {
            _ = ectx.stream.read_byte();
            return .{ .integer = 1 };
        },
        opcodes.ONES_OP => {
            _ = ectx.stream.read_byte();
            // OnesOp = 0xFFFFFFFF for 32-bit mode (§5.7.4)
            return .{ .integer = 0xFFFFFFFF };
        },
        opcodes.BYTE_PREFIX => {
            _ = ectx.stream.read_byte();
            const v = ectx.stream.read_byte() orelse return Error.parse_error;
            return .{ .integer = v };
        },
        opcodes.WORD_PREFIX => {
            _ = ectx.stream.read_byte();
            const v = ectx.stream.read_word() orelse return Error.parse_error;
            return .{ .integer = v };
        },
        opcodes.DWORD_PREFIX => {
            _ = ectx.stream.read_byte();
            const v = ectx.stream.read_dword() orelse return Error.parse_error;
            return .{ .integer = v };
        },
        opcodes.QWORD_PREFIX => {
            _ = ectx.stream.read_byte();
            const v = ectx.stream.read_qword() orelse return Error.parse_error;
            return .{ .integer = v };
        },

        // -- String constant (§20.2.3) --
        opcodes.STRING_PREFIX => {
            _ = ectx.stream.read_byte();
            return string.eval_string(ectx.stream);
        },

        // -- Local0..Local7 (§20.2.6.2) --
        opcodes.LOCAL0...opcodes.LOCAL7 => {
            _ = ectx.stream.read_byte();
            return local_arg.read_local(frame, @truncate(op - opcodes.LOCAL0));
        },

        // -- Arg0..Arg6 (§20.2.6.1) --
        opcodes.ARG0...opcodes.ARG6 => {
            _ = ectx.stream.read_byte();
            return local_arg.read_arg(frame, @truncate(op - opcodes.ARG0));
        },

        // -- Store (§20.2.5.4) --
        opcodes.STORE_OP => {
            _ = ectx.stream.read_byte();
            return store.eval_store(ectx);
        },

        // -- Buffer (§20.2.5.4) --
        opcodes.BUFFER_OP => {
            _ = ectx.stream.read_byte();
            return buffer.eval_buffer(ectx);
        },

        // -- Package / VarPackage (§20.2.5.4) --
        opcodes.PACKAGE_OP => {
            _ = ectx.stream.read_byte();
            return package_mod.eval_package(ectx);
        },
        opcodes.VAR_PACKAGE_OP => {
            _ = ectx.stream.read_byte();
            return package_mod.eval_var_package(ectx);
        },

        // -- Arithmetic (§20.2.5.4) --
        opcodes.ADD_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_add(ectx);
        },
        opcodes.SUBTRACT_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_subtract(ectx);
        },
        opcodes.MULTIPLY_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_multiply(ectx);
        },
        opcodes.DIVIDE_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_divide(ectx);
        },
        opcodes.MOD_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_mod(ectx);
        },
        opcodes.AND_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_and(ectx);
        },
        opcodes.NAND_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_nand(ectx);
        },
        opcodes.OR_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_or(ectx);
        },
        opcodes.NOR_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_nor(ectx);
        },
        opcodes.XOR_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_xor(ectx);
        },
        opcodes.NOT_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_not(ectx);
        },
        opcodes.SHIFT_LEFT_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_shift_left(ectx);
        },
        opcodes.SHIFT_RIGHT_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_shift_right(ectx);
        },
        opcodes.INCREMENT_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_increment(ectx);
        },
        opcodes.DECREMENT_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_decrement(ectx);
        },
        opcodes.FIND_SET_LEFT_BIT_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_find_set_left_bit(ectx);
        },
        opcodes.FIND_SET_RIGHT_BIT_OP => {
            _ = ectx.stream.read_byte();
            return arithmetic.eval_find_set_right_bit(ectx);
        },

        // -- Logical (§20.2.5.4) --
        opcodes.LEQUAL_OP => {
            _ = ectx.stream.read_byte();
            return logical.eval_lequal(ectx);
        },
        opcodes.LGREATER_OP => {
            _ = ectx.stream.read_byte();
            return logical.eval_lgreater(ectx);
        },
        opcodes.LLESS_OP => {
            _ = ectx.stream.read_byte();
            return logical.eval_lless(ectx);
        },
        opcodes.LAND_OP => {
            _ = ectx.stream.read_byte();
            return logical.eval_land(ectx);
        },
        opcodes.LOR_OP => {
            _ = ectx.stream.read_byte();
            return logical.eval_lor(ectx);
        },
        opcodes.LNOT_OP => {
            _ = ectx.stream.read_byte();
            return logical.eval_lnot(ectx);
        },

        // -- Reference ops (§20.2.5.4) --
        opcodes.REF_OF_OP => {
            _ = ectx.stream.read_byte();
            return ref.eval_ref_of(ectx);
        },
        opcodes.DEREF_OF_OP => {
            _ = ectx.stream.read_byte();
            return ref.eval_deref_of(ectx);
        },
        opcodes.INDEX_OP => {
            _ = ectx.stream.read_byte();
            return ref.eval_index(ectx);
        },

        // -- Misc (§20.2.5.4) --
        opcodes.SIZE_OF_OP => {
            _ = ectx.stream.read_byte();
            return misc.eval_size_of(ectx);
        },
        opcodes.OBJECT_TYPE_OP => {
            _ = ectx.stream.read_byte();
            return misc.eval_object_type(ectx);
        },
        opcodes.COPY_OBJECT_OP => {
            _ = ectx.stream.read_byte();
            return misc.eval_copy_object(ectx);
        },

        // -- Conversions (§20.2.5.4) --
        opcodes.TO_INTEGER_OP => {
            _ = ectx.stream.read_byte();
            return convert.eval_to_integer(ectx);
        },
        opcodes.TO_BUFFER_OP => {
            _ = ectx.stream.read_byte();
            return convert.eval_to_buffer(ectx);
        },
        opcodes.TO_HEX_STRING_OP => {
            _ = ectx.stream.read_byte();
            return convert.eval_to_hex_string(ectx);
        },
        opcodes.TO_DEC_STRING_OP => {
            _ = ectx.stream.read_byte();
            return convert.eval_to_decimal_string(ectx);
        },

        // -- Concat / ConcatRes: skip for now (§20.2.5.4) --
        opcodes.CONCAT_OP, opcodes.CONCAT_RES_OP => {
            _ = ectx.stream.read_byte();
            const a = try eval_operand(ectx);
            _ = try eval_operand(ectx);
            skip.skip_target(ectx.stream);
            return a;
        },

        // -- Match: skip for now (§20.2.5.4) --
        opcodes.MATCH_OP => {
            _ = ectx.stream.read_byte();
            skip.skip_term_arg(ectx.stream); // SearchPkg
            _ = ectx.stream.read_byte(); // MatchOpcode1
            skip.skip_term_arg(ectx.stream); // Operand1
            _ = ectx.stream.read_byte(); // MatchOpcode2
            skip.skip_term_arg(ectx.stream); // Operand2
            skip.skip_term_arg(ectx.stream); // StartIndex
            return .{ .integer = 0xFFFFFFFF }; // ONES = not found
        },

        // -- Mid: skip for now (§20.2.5.4) --
        opcodes.MID_OP => {
            _ = ectx.stream.read_byte();
            const obj = try eval_operand(ectx);
            _ = try eval_operand(ectx); // index
            _ = try eval_operand(ectx); // length
            skip.skip_target(ectx.stream);
            return obj;
        },

        // -- ToString (§20.2.5.4) --
        opcodes.TO_STRING_OP => {
            _ = ectx.stream.read_byte();
            const obj = try eval_operand(ectx);
            _ = try eval_operand(ectx); // LengthArg
            skip.skip_target(ectx.stream);
            return obj;
        },

        // -- Extended prefix (§20.3 Table 20.2) --
        opcodes.EXT_PREFIX => {
            return eval_ext_operand(ectx);
        },

        // -- NameString -> method invocation or data object (§20.2.5.4) --
        else => {
            if (path_mod.is_name_start(op)) {
                return method_inv.eval_name_operand(ectx);
            }
            return Error.parse_error;
        },
    }
}

/// Dispatch extended (0x5B XX) operand opcodes.
fn eval_ext_operand(ectx: *EvalContext) Error!Object {
    _ = ectx.stream.read_byte(); // EXT_PREFIX
    const ext = ectx.stream.read_byte() orelse return Error.parse_error;

    switch (ext) {
        // DebugObj (§20.2.6.3)
        opcodes.EXT_DEBUG_OP => return .debug_object,

        // RevisionOp (§20.2.3): returns the AML interpreter revision
        opcodes.EXT_REVISION_OP => return .{ .integer = 1 },

        // TimerOp (§20.2.5.4): simplified, return 0
        opcodes.EXT_TIMER_OP => return .{ .integer = 0 },

        // DefCondRefOf (§20.2.5.4): SuperName Target -> always returns false for now
        opcodes.EXT_COND_REF_OF_OP => {
            skip.skip_super_name(ectx.stream);
            skip.skip_target(ectx.stream);
            return .{ .integer = 0 };
        },

        // DefAcquire (§20.2.5.4): MutexObject Timeout -> always succeeds (single-threaded)
        opcodes.EXT_ACQUIRE_OP => {
            skip.skip_super_name(ectx.stream);
            _ = ectx.stream.read_word(); // Timeout
            return .{ .integer = 0 }; // 0 = success
        },

        // DefFromBCD / DefToBCD (§20.2.5.4)
        opcodes.EXT_FROM_BCD_OP => return convert.eval_from_bcd(ectx),
        opcodes.EXT_TO_BCD_OP => return convert.eval_to_bcd(ectx),

        else => return .uninitialized,
    }
}
