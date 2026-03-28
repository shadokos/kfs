/// AML statement (control flow) opcodes (ACPI 6.4 §20.2.5.3).
///
/// DefIfElse  := IfOp PkgLength Predicate TermList DefElse   (§20.2.5.3)
/// DefElse    := Nothing | <ElseOp PkgLength TermList>       (§20.2.5.3)
/// DefWhile   := WhileOp PkgLength Predicate TermList        (§20.2.5.3)
/// DefReturn  := ReturnOp ArgObject                          (§20.2.5.3)
/// DefBreak   := BreakOp                                     (§20.2.5.3)
/// DefContinue := ContinueOp                                 (§20.2.5.3)
/// DefNoop    := NoopOp                                      (§20.2.5.3)
const std = @import("std");
const parser = @import("../parser.zig");
const opcodes = @import("../opcodes.zig");
const objects = @import("../objects.zig");
const integer = @import("integer.zig");

const Object = objects.Object;
const Stream = parser.Stream;
const Error = @import("executor.zig").Error;
const EvalContext = @import("executor.zig").EvalContext;

const to_int = integer.to_int;
const log = std.log.scoped(.acpi_exec);

fn eval_operand(ectx: *EvalContext) Error!Object {
    return @import("operand.zig").eval_operand(ectx);
}

fn eval_term(ectx: *EvalContext) Error!?Object {
    return @import("term.zig").eval_term(ectx);
}

/// Implementation-defined maximum while loop iterations (safety bound).
const MAX_ITERATIONS: u32 = 10_000;

/// DefIfElse := IfOp PkgLength Predicate TermList DefElse (§20.2.5.3).
/// IfOp (0xA0) must already be consumed.
pub fn eval_if_else(ectx: *EvalContext) Error!?Object {
    const pkg = parser.decode_pkg_length(ectx.stream) orelse
        return Error.parse_error;
    const end_pos = ectx.stream.pos + pkg.body_length;

    // Evaluate predicate (§20.2.5.3: Predicate := TermArg => Integer)
    const predicate = to_int(try eval_operand(ectx));

    if (predicate != 0) {
        // Execute the if-body TermList
        while (ectx.stream.pos < end_pos) {
            if (try eval_term(ectx)) |ret| {
                ectx.stream.pos = @min(end_pos, ectx.stream.data.len);
                // Must still skip Else block if present
                skip_else(ectx);
                return ret;
            }
            const frame = ectx.ctx.current() orelse break;
            if (frame.break_pending) break;
        }
    }
    ectx.stream.pos = @min(end_pos, ectx.stream.data.len);

    // Check for DefElse (§20.2.5.3: DefElse := Nothing | <ElseOp PkgLength TermList>)
    if (ectx.stream.peek()) |next| {
        if (next == opcodes.ELSE_OP) {
            _ = ectx.stream.read_byte();
            const else_pkg = parser.decode_pkg_length(ectx.stream) orelse
                return Error.parse_error;
            const else_end = ectx.stream.pos + else_pkg.body_length;

            const frame = ectx.ctx.current();
            if (predicate == 0 and (frame == null or !frame.?.break_pending)) {
                while (ectx.stream.pos < else_end) {
                    if (try eval_term(ectx)) |ret| {
                        ectx.stream.pos = @min(else_end, ectx.stream.data.len);
                        return ret;
                    }
                    const f = ectx.ctx.current() orelse break;
                    if (f.break_pending) break;
                }
            }
            ectx.stream.pos = @min(else_end, ectx.stream.data.len);
        }
    }
    return null;
}

/// DefWhile := WhileOp PkgLength Predicate TermList (§20.2.5.3).
/// WhileOp (0xA2) must already be consumed.
pub fn eval_while(ectx: *EvalContext) Error!?Object {
    const pkg = parser.decode_pkg_length(ectx.stream) orelse
        return Error.parse_error;
    const end_pos = ectx.stream.pos + pkg.body_length;
    const body_start = ectx.stream.pos;
    var iterations: u32 = 0;

    while (iterations < MAX_ITERATIONS) : (iterations += 1) {
        ectx.stream.pos = body_start;

        // Evaluate predicate
        const predicate = to_int(try eval_operand(ectx));
        if (predicate == 0) break;

        // Execute body TermList
        while (ectx.stream.pos < end_pos) {
            if (try eval_term(ectx)) |ret| {
                ectx.stream.pos = @min(end_pos, ectx.stream.data.len);
                return ret;
            }
            const frame = ectx.ctx.current() orelse break;
            if (frame.break_pending or frame.continue_pending) break;
        }

        // Check break/continue flags
        if (ectx.ctx.current()) |frame| {
            if (frame.break_pending) {
                frame.break_pending = false;
                break;
            }
            if (frame.continue_pending) {
                frame.continue_pending = false;
                // Continue: skip to next iteration (predicate re-eval)
            }
        }
    }

    if (iterations >= MAX_ITERATIONS) {
        log.warn("While loop hit MAX_ITERATIONS ({d})", .{MAX_ITERATIONS});
    }

    ectx.stream.pos = @min(end_pos, ectx.stream.data.len);
    return null;
}

/// DefReturn := ReturnOp ArgObject (§20.2.5.3, ReturnOp = 0xA4).
/// ReturnOp must already be consumed.
pub fn eval_return(ectx: *EvalContext) Error!?Object {
    return try eval_operand(ectx);
}

/// DefBreak := BreakOp (§20.2.5.3, BreakOp = 0xA5).
/// BreakOp must already be consumed.
pub fn eval_break(ectx: *EvalContext) Error!?Object {
    if (ectx.ctx.current()) |frame| {
        frame.break_pending = true;
    }
    return null;
}

/// DefContinue := ContinueOp (§20.2.5.3, ContinueOp = 0x9F).
/// Skips the rest of the current While body and restarts at the predicate.
pub fn eval_continue(ectx: *EvalContext) Error!?Object {
    if (ectx.ctx.current()) |frame| {
        frame.continue_pending = true;
    }
    return null;
}

/// Skip past a DefElse block if present, without executing.
fn skip_else(ectx: *EvalContext) void {
    if (ectx.stream.peek()) |next| {
        if (next == opcodes.ELSE_OP) {
            _ = ectx.stream.read_byte();
            const else_pkg = parser.decode_pkg_length(ectx.stream) orelse return;
            ectx.stream.pos = @min(
                ectx.stream.pos + else_pkg.body_length,
                ectx.stream.data.len,
            );
        }
    }
}
