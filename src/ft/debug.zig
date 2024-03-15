pub const StackIterator = struct {
    // skip every frame before this address is found
    first_address: ?usize,
    fp: usize,

    pub fn init(first_address: ?usize, fp: ?usize) StackIterator {
        return StackIterator{
            .first_address = first_address,
            .fp = fp orelse @frameAddress(),
        };
    }

    const pc_offset = @sizeOf(usize);

    pub fn next(self: *StackIterator) ?usize {
        var address = self.next_internal() orelse return null;

        if (self.first_address) |first_address| {
            while (address != first_address) {
                address = self.next_internal() orelse return null;
            }
            self.first_address = null;
        }

        return address;
    }

    fn next_internal(self: *StackIterator) ?usize {
        const fp = self.fp;

        // Sanity check.
        const mem = @import("../ft/ft.zig").mem;
        if (fp == 0 or !mem.isAligned(fp, @alignOf(usize)))
            return null;

        const new_fp = @as(*const usize, @ptrFromInt(fp)).*;

        if (new_fp != 0 and new_fp < self.fp)
            return null;

        const new_pc = @as(*const usize, @ptrFromInt(fp + pc_offset)).*;

        self.fp = new_fp;

        return new_pc;
    }
};

// https://ziglang.org/documentation/master/std/#std.debug.assert
pub fn assert(ok: bool) void {
    if (!ok) unreachable; // assertion failure
}
