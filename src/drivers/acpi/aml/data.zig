/// AML data object parsing (§20.2.3 ComputationalData, §20.2.5.4 DefBuffer/DefPackage).
///
/// Parses ComputationalData and DataObject from the AML bytecode stream
/// without evaluating expressions. Used during namespace loading to
/// populate DefName object values.
const parser = @import("parser.zig");
const opcodes = @import("opcodes.zig");
const objects = @import("objects.zig");
const skip = @import("skip.zig");

const Stream = parser.Stream;
const Object = objects.Object;

/// Parse a DataObject from the stream and return the corresponding Object.
/// Handles integer constants, strings, buffers, and packages.
/// Returns .uninitialized if the data cannot be parsed.
pub fn parse_data_object(stream: *Stream) Object {
    const op = stream.peek() orelse return .uninitialized;

    switch (op) {
        opcodes.ZERO_OP => {
            _ = stream.read_byte();
            return .{ .integer = 0 };
        },
        opcodes.ONE_OP => {
            _ = stream.read_byte();
            return .{ .integer = 1 };
        },
        opcodes.ONES_OP => {
            _ = stream.read_byte();
            return .{ .integer = 0xFFFFFFFFFFFFFFFF };
        },
        opcodes.BYTE_PREFIX => {
            _ = stream.read_byte();
            const val = stream.read_byte() orelse return .uninitialized;
            return .{ .integer = val };
        },
        opcodes.WORD_PREFIX => {
            _ = stream.read_byte();
            const val = stream.read_word() orelse return .uninitialized;
            return .{ .integer = val };
        },
        opcodes.DWORD_PREFIX => {
            _ = stream.read_byte();
            const val = stream.read_dword() orelse return .uninitialized;
            return .{ .integer = val };
        },
        opcodes.QWORD_PREFIX => {
            _ = stream.read_byte();
            const val = stream.read_qword() orelse return .uninitialized;
            return .{ .integer = val };
        },
        opcodes.STRING_PREFIX => {
            _ = stream.read_byte();
            const start = stream.pos;
            while (stream.pos < stream.data.len and
                stream.data[stream.pos] != 0)
            {
                stream.pos += 1;
            }
            const str = stream.data[start..stream.pos];
            if (stream.pos < stream.data.len) stream.pos += 1; // skip null terminator
            return .{ .string = str };
        },
        opcodes.BUFFER_OP => {
            _ = stream.read_byte();
            const pkg = parser.decode_pkg_length(stream) orelse
                return .uninitialized;
            const end = stream.pos + pkg.body_length;
            // Skip buffer size (term arg)
            skip.skip_term_arg(stream);
            const buf_data = if (end > stream.pos)
                stream.data[stream.pos..end]
            else
                &[_]u8{};
            stream.pos = @min(end, stream.data.len);
            // Buffer data is a slice into the DSDT/SSDT bytecode (not owned).
            // Safe only for the lifetime of the AML table mapping.
            return .{ .buffer = .{ .data = @constCast(buf_data) } };
        },
        opcodes.PACKAGE_OP, opcodes.VAR_PACKAGE_OP => {
            _ = stream.read_byte();
            const pkg = parser.decode_pkg_length(stream) orelse
                return .uninitialized;
            const end = stream.pos + pkg.body_length;
            // Skip package contents (no allocation during loading phase)
            stream.pos = @min(end, stream.data.len);
            return .{ .package = .{ .elements = &.{} } };
        },
        else => {
            // Unknown data object, skip one term arg
            skip.skip_term_arg(stream);
            return .uninitialized;
        },
    }
}

/// Parse an integer from a data constant prefix (§20.2.3).
/// Returns 0 for unrecognized prefixes.
pub fn parse_integer_data(stream: *Stream) u64 {
    const op = stream.peek() orelse return 0;
    switch (op) {
        opcodes.ZERO_OP => {
            _ = stream.read_byte();
            return 0;
        },
        opcodes.ONE_OP => {
            _ = stream.read_byte();
            return 1;
        },
        opcodes.ONES_OP => {
            _ = stream.read_byte();
            return 0xFFFFFFFFFFFFFFFF;
        },
        opcodes.BYTE_PREFIX => {
            _ = stream.read_byte();
            return stream.read_byte() orelse 0;
        },
        opcodes.WORD_PREFIX => {
            _ = stream.read_byte();
            return stream.read_word() orelse 0;
        },
        opcodes.DWORD_PREFIX => {
            _ = stream.read_byte();
            return stream.read_dword() orelse 0;
        },
        opcodes.QWORD_PREFIX => {
            _ = stream.read_byte();
            return stream.read_qword() orelse 0;
        },
        else => return 0,
    }
}
