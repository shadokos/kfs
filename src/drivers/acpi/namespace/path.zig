/// AML Name Path parsing utilities.
///
/// AML name objects encoding per ACPI 6.4 §20.2.2:
///   NameSeg          := [A-Z_][A-Z0-9_]{3}   (4 chars, padded with '_')
///   NullName         := 0x00
///   DualNamePath     := 0x2E NameSeg NameSeg
///   MultiNamePath    := 0x2F SegCount NameSeg*  (SegCount: 1–255)
///   RootChar         := 0x5C '\'
///   ParentPrefixChar := 0x5E '^'
const std = @import("std");

pub const NameSeg = [4]u8;

/// §20.2.2 AML name encoding constants.
pub const NULLNAME: u8 = 0x00;
pub const DUAL_NAME_PREFIX: u8 = 0x2E;
pub const MULTI_NAME_PREFIX: u8 = 0x2F;
pub const ROOT_PREFIX: u8 = 0x5C; // RootChar '\'
pub const PARENT_PREFIX: u8 = 0x5E; // ParentPrefixChar '^'

/// Maximum number of segments in a MultiNamePath.
/// SegCount is encoded as a single byte (§20.2.2), so the range is 1–255.
pub const MAX_SEGMENTS: usize = 255;

pub const ParsedPath = struct {
    /// Number of parent prefixes ('^') to ascend (§20.2.2 ParentPrefixChar).
    parent_count: u8 = 0,
    /// Whether the path is absolute (starts with '\', §20.2.2 RootChar).
    is_absolute: bool = false,
    /// The name segments in the path. Owned by the caller; free with deinit().
    segments: []const NameSeg,
    /// Bytes consumed from the AML stream.
    bytes_consumed: usize = 0,

    /// Free the segments slice. Safe to call when segments is empty (no allocation was made).
    pub fn deinit(self: *const ParsedPath, alloc: std.mem.Allocator) void {
        if (self.segments.len > 0) {
            alloc.free(self.segments);
        }
    }
};

/// Returns true if a byte is a valid lead character for a NameSeg (§20.2.2).
pub fn is_name_lead(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or c == '_';
}

/// Returns true if a byte is a valid non-lead character for a NameSeg (§20.2.2).
pub fn is_name_char(c: u8) bool {
    return is_name_lead(c) or (c >= '0' and c <= '9');
}

/// Returns true if the byte could start a NamePath in AML (§20.2.2).
/// Includes NullName (0x00) which is a valid NamePath per §20.2.2.
pub fn is_name_start(c: u8) bool {
    return is_name_lead(c) or c == ROOT_PREFIX or
        c == PARENT_PREFIX or c == DUAL_NAME_PREFIX or
        c == MULTI_NAME_PREFIX or c == NULLNAME;
}

/// Parse a NamePath from AML bytecode (§20.2.2).
///
/// Returns null if the data does not form a valid NamePath.
/// Returns a ParsedPath with segments.len == 0 for NullName or prefix-only paths.
/// On success the caller owns the segments slice and must call ParsedPath.deinit(alloc).
pub fn parse(alloc: std.mem.Allocator, data: []const u8) error{OutOfMemory}!?ParsedPath {
    if (data.len == 0) return null;

    var pos: usize = 0;
    var result: ParsedPath = .{
        .segments = &.{},
    };

    // Handle RootChar (§20.2.2: 0x5C)
    if (data[pos] == ROOT_PREFIX) {
        result.is_absolute = true;
        pos += 1;
        if (pos >= data.len) {
            result.bytes_consumed = pos;
            return result;
        }
    }

    // Handle ParentPrefixChar (§20.2.2: 0x5E '^'), zero or more
    while (pos < data.len and data[pos] == PARENT_PREFIX) {
        result.parent_count += 1;
        pos += 1;
    }

    if (pos >= data.len) {
        result.bytes_consumed = pos;
        return result;
    }

    // NullName (§20.2.2: 0x00): zero-segment path
    if (data[pos] == NULLNAME) {
        result.bytes_consumed = pos + 1;
        return result;
    }

    // DualNamePath (§20.2.2: 0x2E NameSeg NameSeg)
    if (data[pos] == DUAL_NAME_PREFIX) {
        pos += 1;
        if (pos + 8 > data.len) return null;
        const segs = try alloc.alloc(NameSeg, 2);
        segs[0] = data[pos..][0..4].*;
        segs[1] = data[pos + 4 ..][0..4].*;
        result.segments = segs;
        result.bytes_consumed = pos + 8;
        return result;
    }

    // MultiNamePath (§20.2.2: 0x2F SegCount NameSeg*, SegCount 1–255)
    if (data[pos] == MULTI_NAME_PREFIX) {
        pos += 1;
        if (pos >= data.len) return null;
        const count = data[pos];
        pos += 1;
        if (pos + @as(usize, count) * 4 > data.len) return null;
        const segs = try alloc.alloc(NameSeg, count);
        for (0..count) |i| {
            segs[i] = data[pos..][0..4].*;
            pos += 4;
        }
        result.segments = segs;
        result.bytes_consumed = pos;
        return result;
    }

    // Single NameSeg (§20.2.2)
    if (is_name_lead(data[pos])) {
        if (pos + 4 > data.len) return null;
        const segs = try alloc.alloc(NameSeg, 1);
        segs[0] = data[pos..][0..4].*;
        result.segments = segs;
        result.bytes_consumed = pos + 4;
        return result;
    }

    return null;
}

/// Format a NameSeg for display (trim trailing underscores).
pub fn format_seg(seg: *const NameSeg) []const u8 {
    var len: usize = 4;
    while (len > 0 and seg[len - 1] == '_') len -= 1;
    return seg[0..len];
}
