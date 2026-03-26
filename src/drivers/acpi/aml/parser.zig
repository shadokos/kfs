/// AML bytecode stream reader and PkgLength decoder.
///
/// The Stream provides sequential access to AML bytecode with
/// little-endian multi-byte reads matching the AML data encodings
/// defined in ACPI 6.4 §20.2.3 (ByteData, WordData, DWordData, QWordData).
///
/// PkgLength decoding follows §20.2.4 "Package Length Encoding".
const std = @import("std");

/// Sequential reader over an AML bytecode buffer.
///
/// AML bytecode is a linear byte stream (§20 "AML Specification").
/// Multi-byte integers are stored in little-endian order (§20.2.3).
pub const Stream = struct {
    data: []const u8,
    pos: usize = 0,

    /// Number of bytes remaining in the stream.
    pub fn remaining(self: *const Stream) usize {
        return self.data.len -| self.pos;
    }

    /// Returns true when the stream is fully consumed.
    pub fn eof(self: *const Stream) bool {
        return self.pos >= self.data.len;
    }

    /// Peek at the next byte without advancing the position.
    pub fn peek(self: *const Stream) ?u8 {
        if (self.pos >= self.data.len) return null;
        return self.data[self.pos];
    }

    /// Read a single ByteData (§20.2.3) and advance past it.
    pub fn read_byte(self: *Stream) ?u8 {
        if (self.pos >= self.data.len) return null;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    /// Read a little-endian integer of type T from the stream (§20.2.3).
    /// T must be u16, u32, or u64 (matching WordData, DWordData, QWordData).
    fn readInt(self: *Stream, comptime T: type) ?T {
        const size = @sizeOf(T);
        if (self.pos + size > self.data.len) return null;
        const val = std.mem.readInt(T, self.data[self.pos..][0..size], .little);
        self.pos += size;
        return val;
    }

    /// Read a little-endian WordData (§20.2.3, 16-bit) and advance past it.
    pub fn read_word(self: *Stream) ?u16 {
        return self.readInt(u16);
    }

    /// Read a little-endian DWordData (§20.2.3, 32-bit) and advance past it.
    pub fn read_dword(self: *Stream) ?u32 {
        return self.readInt(u32);
    }

    /// Read a little-endian QWordData (§20.2.3, 64-bit) and advance past it.
    pub fn read_qword(self: *Stream) ?u64 {
        return self.readInt(u64);
    }

    /// Read exactly `len` raw bytes and advance past them.
    pub fn read_bytes(self: *Stream, len: usize) ?[]const u8 {
        if (self.pos + len > self.data.len) return null;
        const slice = self.data[self.pos .. self.pos + len];
        self.pos += len;
        return slice;
    }

    /// Skip ahead n bytes.
    pub fn skip(self: *Stream, n: usize) void {
        self.pos = @min(self.pos + n, self.data.len);
    }

    /// Create a sub-stream from current position with given length.
    /// The parent stream is advanced past the sub-stream region.
    pub fn sub_stream(self: *Stream, len: usize) ?Stream {
        if (self.pos + len > self.data.len) return null;
        const sub = Stream{
            .data = self.data[self.pos .. self.pos + len],
        };
        self.pos += len;
        return sub;
    }
};

/// Decode an AML PkgLength from a bytecode stream (§20.2.4).
///
/// Grammar (§20.2.4):
///   PkgLength := PkgLeadByte |
///                <PkgLeadByte ByteData> |
///                <PkgLeadByte ByteData ByteData> |
///                <PkgLeadByte ByteData ByteData ByteData>
///
///   PkgLeadByte :=
///     bit 7-6 : ByteData count that follows (0-3)
///     bit 5-4 : only used if PkgLength < 63 (i.e. follow count == 0)
///     bit 3-0 : least significant package length nibble
///
/// When follow count == 0, bits [5:0] encode the total length (range 0-63).
/// When follow count >= 1, bits [5:4] are reserved (must be zero) and
/// bits [3:0] are the least significant nibble; subsequent bytes provide
/// the remaining bits in little-endian order.
///
/// Maximum encodable lengths per byte count (§20.2.4):
///   1 byte  : 0x3F        (63)
///   2 bytes : 0x0FFF      (4095)
///   3 bytes : 0x0FFFFF    (1048575)
///   4 bytes : 0x0FFFFFFF  (2^28 - 1)
///
/// The returned length is the "body length": the total PkgLength value
/// minus the bytes consumed by the PkgLength encoding itself, since the
/// PkgLength value includes itself (§20.2.4).
pub fn decode_pkg_length(stream: *Stream) ?PkgLengthResult {
    const start = stream.pos;
    const lead = stream.read_byte() orelse return null;
    const follow_count: u2 = @truncate(lead >> 6);

    var length: u32 = 0;

    if (follow_count == 0) {
        // Single-byte encoding: bits [5:0] hold the total length (§20.2.4).
        length = lead & 0x3F;
    } else {
        // Multi-byte encoding: bits [3:0] of lead are the least significant
        // nibble; follow bytes provide the rest in little-endian order (§20.2.4).
        length = lead & 0x0F;
        for (0..follow_count) |i| {
            const b = stream.read_byte() orelse return null;
            length |= @as(u32, b) << @intCast(4 + i * 8);
        }
    }

    const bytes_consumed = stream.pos - start;

    // PkgLength includes its own encoding bytes (§20.2.4).
    // The body length is what remains after subtracting them.
    if (length < bytes_consumed) return null;
    const body_length = length - @as(u32, @intCast(bytes_consumed));

    return .{
        .total_length = length,
        .body_length = body_length,
        .header_size = @intCast(bytes_consumed),
    };
}

/// Result of decoding a PkgLength (§20.2.4).
pub const PkgLengthResult = struct {
    /// Total length including the PkgLength encoding bytes.
    total_length: u32,
    /// Length of the body (total minus PkgLength header bytes).
    body_length: u32,
    /// Number of bytes consumed by the PkgLength encoding (1-4).
    header_size: u8,
};
