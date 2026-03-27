/// Local and Arg variable access (ACPI 6.4 §20.2.6).
///
/// LocalObj := Local0Op .. Local7Op   (0x60..0x67, §20.2.6.2)
/// ArgObj   := Arg0Op   .. Arg6Op    (0x68..0x6E, §20.2.6.1)
///
/// "Control methods can access up to eight local data objects" (§5.5.2.3).
/// "Up to seven arguments can be passed to a control method" (§5.5.2.1).
const context_mod = @import("../context.zig");
const objects = @import("../objects.zig");
const opcodes = @import("../opcodes.zig");

const Object = objects.Object;
const MethodFrame = context_mod.MethodFrame;

/// Read Local0..Local7. `idx` must be 0..7.
pub fn read_local(frame: *const MethodFrame, idx: u3) Object {
    return frame.locals[idx];
}

/// Read Arg0..Arg6. `idx` must be 0..6.
pub fn read_arg(frame: *const MethodFrame, idx: u3) Object {
    return frame.args[idx];
}

/// Write Local0..Local7. `idx` must be 0..7.
pub fn write_local(frame: *MethodFrame, idx: u3, value: Object) void {
    frame.locals[idx] = value;
}

/// Write Arg0..Arg6. `idx` must be 0..6.
pub fn write_arg(frame: *MethodFrame, idx: u3, value: Object) void {
    frame.args[idx] = value;
}
