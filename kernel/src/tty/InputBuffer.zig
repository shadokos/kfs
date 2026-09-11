// What the line discipline has produced and read() has not taken yet.
//
//     tail ......... canon_head ......... head
//     where read     end of the last      where the discipline
//     takes          completed line       writes
//
// A canonical read may only reach canon_head, and erasing may not go back past
// it. Outside canonical mode every byte is complete on arrival, so canon_head
// follows head. Nothing raw is kept.

const std = @import("std");

/// POSIX {MAX_INPUT}: how much unread input a terminal will hold.
pub const MAX_INPUT: usize = 4096;

comptime {
    if (@popCount(MAX_INPUT) != 1)
        @compileError("MAX_INPUT must be a power of two, the positions wrap on it");
}

/// Wraps on MAX_INPUT of its own accord, so stepping a position is `+%= 1`.
pub const Index = std.meta.Int(.unsigned, std.math.log2(MAX_INPUT));

const Self = @This();

buffer: [MAX_INPUT]u8 = undefined,

/// Where the line discipline writes.
head: Index = 0,

/// Where read() takes.
tail: Index = 0,

/// End of the last completed line.
canon_head: Index = 0,

/// One position is left unused, or a full ring would look like an empty one.
pub fn is_full(self: *const Self) bool {
    return self.head +% 1 == self.tail;
}

/// Bytes held, complete or not.
pub fn count(self: *const Self) Index {
    return self.head -% self.tail;
}

/// Bytes a canonical read may take.
pub fn canon_count(self: *const Self) Index {
    return self.canon_head -% self.tail;
}

/// Add a processed byte. Dropped once the ring is full, which is what a finite
/// {MAX_INPUT} means.
pub fn push(self: *Self, c: u8) void {
    if (self.is_full()) return;
    self.buffer[self.head] = c;
    self.head +%= 1;
}

/// Publish everything written so far as readable.
pub fn commit(self: *Self) void {
    self.canon_head = self.head;
}

/// Take back the last byte written. Null when the line being edited is empty.
pub fn erase(self: *Self) ?u8 {
    if (self.head == self.canon_head) return null;
    self.head -%= 1;
    return self.buffer[self.head];
}

/// Take the oldest byte. Null when there is none.
pub fn pop(self: *Self) ?u8 {
    if (self.tail == self.head) return null;
    const c = self.buffer[self.tail];
    self.tail +%= 1;
    return c;
}

/// Drop everything, read or half typed.
pub fn clear(self: *Self) void {
    self.head = self.tail;
    self.canon_head = self.tail;
}
