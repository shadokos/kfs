const interrupt = @import("../interrupts.zig");
const InterruptFrame = interrupt.InterruptFrame;
const frame_stack = &interrupt.frame_stack;

pub const Id = 4;

pub fn do_raw(frame: *InterruptFrame) void {
    if (frame_stack.* == null) return;
    if (frame_stack.*.?.popOrNull()) |v| frame.* = v;
}
