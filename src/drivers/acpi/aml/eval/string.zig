/// AML string constant evaluation (ACPI 6.4 §20.2.3).
///
/// String := StringPrefix AsciiCharList NullChar
/// StringPrefix := 0x0D
/// AsciiCharList := Nothing | <AsciiChar AsciiCharList>
/// NullChar := 0x00
const parser = @import("../parser.zig");
const objects = @import("../objects.zig");

const Stream = parser.Stream;
const Object = objects.Object;
const Error = @import("executor.zig").Error;

/// Parse a null-terminated AsciiString from the stream (§20.2.3).
/// StringPrefix (0x0D) must already be consumed by the caller.
pub fn eval_string(stream: *Stream) Error!Object {
    const start = stream.pos;
    while (stream.pos < stream.data.len and stream.data[stream.pos] != 0) {
        stream.pos += 1;
    }
    const str = stream.data[start..stream.pos];
    // Skip the null terminator
    if (stream.pos < stream.data.len) stream.pos += 1;
    return .{ .string = str };
}
