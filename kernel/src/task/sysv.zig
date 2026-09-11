const std = @import("std");
const elf = @import("elf.zig");
const paging = @import("../memory/paging.zig");

/// Most auxv entries we ever emit: AT_PHDR, AT_PHENT, AT_PHNUM, AT_ENTRY, AT_PAGESZ
/// and the mandatory AT_NULL terminator.
const max_auxv = 6;

pub const arg_max = 128 * 1024;

pub const SysvLayout = struct {
    const Self = @This();

    /// total size in bytes of argv/envp strings, NUL terminators included
    strs_len: usize,
    /// argc, the argv pointers, their NULL, the envp pointers and their NULL
    n_words: usize,
    auxv_buf: [max_auxv]std.elf.Auxv,
    auxv_len: usize,

    pub fn init(argv: []const [:0]const u8, envp: []const [:0]const u8, image: elf.Image) Self {
        var self: Self = .{
            .strs_len = 0,
            .n_words = 1 + argv.len + 1 + envp.len + 1,
            .auxv_buf = undefined,
            .auxv_len = 0,
        };
        for (argv) |arg| self.strs_len += arg.len + 1;
        for (envp) |env| self.strs_len += env.len + 1;
        self.auxv_len = build_auxv(image, &self.auxv_buf).len;
        return self;
    }

    fn auxv_bytes(self: *const Self) []const u8 {
        return std.mem.sliceAsBytes(self.auxv_buf[0..self.auxv_len]);
    }

    fn build_auxv(image: elf.Image, buf: *[max_auxv]std.elf.Auxv) []std.elf.Auxv {
        var len: usize = 0;

        // refering to the sysv i386 ABI:
        // - If the AT_PHDR entry is present, entries of types AT_PHENT, AT_PHNUM, and AT_ENTRY must also be present.
        // Note: That is an implication, not an equivalence: AT_ENTRY alone would be legal, and still informative for
        // an image with no program header table.
        if (image.phdr_vaddr != 0) {
            buf[0] = .{ .a_type = std.elf.AT_PHDR, .a_un = .{ .a_val = image.phdr_vaddr } };
            buf[1] = .{ .a_type = std.elf.AT_PHENT, .a_un = .{ .a_val = image.phentsize } };
            buf[2] = .{ .a_type = std.elf.AT_PHNUM, .a_un = .{ .a_val = image.phnum } };
            len += 3;
        }
        buf[len] = .{ .a_type = std.elf.AT_ENTRY, .a_un = .{ .a_val = image.entry } };
        buf[len + 1] = .{ .a_type = std.elf.AT_PAGESZ, .a_un = .{ .a_val = paging.page_size } };
        buf[len + 2] = .{ .a_type = std.elf.AT_NULL, .a_un = .{ .a_val = 0 } };
        return buf[0 .. len + 3];
    }

    /// Upper bound on the bytes the entry block occupies below `stack_top`. The trailing
    /// 16 bytes cover the padding that aligning the final stack pointer may consume.
    pub fn size(self: *const Self) usize {
        return self.strs_len + self.n_words * @sizeOf(usize) + self.auxv_bytes().len + 16;
    }
};

/// The pointer table fills upwards from the bottom of the entry block, and the
/// strings fill upwards from the base of the string area packed against
/// stack_top. Both grow in push order, so argv[0] lands at the lowest string
/// address following the classic Unix layout some programs expect.
/// SysvLayout.size() guarantees the two areas never overlap.
const Builder = struct {
    const Self = @This();

    words: [*]usize,
    count: usize = 0,
    /// Next free byte in the string area.
    str_next: usize,

    fn push_word(self: *Self, value: usize) void {
        self.words[self.count] = value;
        self.count += 1;
    }

    /// Copy str (NUL terminator included) into the string area, then push its address.
    fn push_str(self: *Self, str: [:0]const u8) void {
        const len = str.len + 1;
        const dst: [*]u8 = @ptrFromInt(self.str_next);
        @memcpy(dst[0..len], str.ptr[0..len]);
        self.push_word(self.str_next);
        self.str_next += len;
    }

    fn push_vector(self: *Self, strs: []const [:0]const u8) void {
        for (strs) |str| self.push_str(str);
        self.push_word(0);
    }
};

/// Build the sysv i386 entry block at the top of a mapped user stack and return the
/// initial esp, pointing at argc and 16-byte aligned as the ABI requires.
pub fn build_sysv_stack(
    stack_top: usize,
    argv: []const [:0]const u8,
    envp: []const [:0]const u8,
    image: elf.Image,
) usize {
    const layout = SysvLayout.init(argv, envp, image);
    const stack_ptr = std.mem.alignBackward(usize, stack_top - layout.size(), 16);
    const strs_base = stack_top - layout.strs_len;

    var builder: Builder = .{ .words = @ptrFromInt(stack_ptr), .str_next = strs_base };
    builder.push_word(argv.len); // argc
    builder.push_vector(argv);
    builder.push_vector(envp);
    std.debug.assert(builder.count == layout.n_words);
    std.debug.assert(builder.str_next == stack_top);

    const auxv = layout.auxv_bytes();
    const auxv_at = stack_ptr + builder.count * @sizeOf(usize);
    std.debug.assert(auxv_at + auxv.len <= strs_base);

    const dst: [*]u8 = @ptrFromInt(auxv_at);
    @memcpy(dst[0..auxv.len], auxv);

    return stack_ptr;
}
