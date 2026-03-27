/// AML data object parsing (§20.2.3 ComputationalData, §20.2.5.4 DefBuffer/DefPackage).
///
/// Parses ComputationalData and DataObject from the AML bytecode stream
/// without evaluating expressions. Used during namespace loading to
/// populate DefName object values.
const parser = @import("parser.zig");
const opcodes = @import("opcodes.zig");
const objects = @import("objects.zig");
const skip = @import("skip.zig");
const osl = @import("../os_layer.zig");
const path_mod = @import("../namespace/path.zig");

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

            // NumElements: ByteData for PackageOp, integer data for VarPackageOp (§20.2.5.4)
            const num_elements: usize = if (op == opcodes.VAR_PACKAGE_OP)
                @as(usize, @intCast(parse_integer_data(stream)))
            else
                stream.read_byte() orelse {
                    stream.pos = @min(end, stream.data.len);
                    return .uninitialized;
                };

            if (num_elements == 0 or num_elements > 255) {
                stream.pos = @min(end, stream.data.len);
                return .{ .package = .{ .elements = &.{} } };
            }

            const elements = osl.kmalloc(Object, num_elements) orelse {
                stream.pos = @min(end, stream.data.len);
                return .{ .package = .{ .elements = &.{} } };
            };

            // Parse PackageElementList (§20.2.5.4):
            // PackageElement := DataRefObject | NameString
            var i: usize = 0;
            while (stream.pos < end and i < num_elements) : (i += 1) {
                elements[i] = parse_package_element(stream);
            }
            // Fill remaining elements with .uninitialized
            while (i < num_elements) : (i += 1) {
                elements[i] = .uninitialized;
            }

            stream.pos = @min(end, stream.data.len);
            return .{ .package = .{ .elements = elements } };
        },
        else => {
            // Unknown data object, skip one term arg
            skip.skip_term_arg(stream);
            return .uninitialized;
        },
    }
}

/// Parse a single PackageElement (§20.2.5.4).
/// PackageElement := DataRefObject | NameString
///
/// NameStrings inside packages reference other namespace objects.
/// Stored as .string with raw AML bytes during loading; the post-load
/// fixup pass (Namespace.resolve_references) converts them to .reference.
fn parse_package_element(stream: *Stream) Object {
    const b = stream.peek() orelse return .uninitialized;

    // NameString starts with a lead name char, RootChar, ParentPrefixChar,
    // DualNamePrefix, or MultiNamePrefix (§20.2.2)
    if (path_mod.is_name_lead(b) or b == path_mod.ROOT_PREFIX or
        b == path_mod.PARENT_PREFIX or b == path_mod.DUAL_NAME_PREFIX or
        b == path_mod.MULTI_NAME_PREFIX)
    {
        const start = stream.pos;
        skip.skip_name_path(stream);
        const name_len = stream.pos - start;
        if (name_len > 0 and name_len < 256) {
            return .{ .string = stream.data[start..stream.pos] };
        }
        return .uninitialized;
    }

    return parse_data_object(stream);
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
