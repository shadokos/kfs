const std = @import("std");
const elf = @import("elf.zig");
const cpu = @import("../cpu.zig");
const paging = @import("../memory/paging.zig");

/// Most auxv entries we ever emit: AT_PHDR, AT_PHENT, AT_PHNUM, AT_ENTRY,
/// AT_PAGESZ, AT_RANDOM, AT_SECURE, AT_EXECFN and the mandatory AT_NULL
/// terminator.
const max_auxv = 9;

/// Bytes of entropy AT_RANDOM points at. Only the first word feeds mlibc's
/// stack guard, but the vector is what userspace expects to find.
const random_len = 16;

pub const arg_max = 128 * 1024;

/// No entropy source in the kernel yet, so this is seeded from the cycle
/// counter. Enough to stop the stack guard from being a compile-time constant,
/// not enough to be treated as cryptographic material.
var prng: ?std.Random.DefaultPrng = null;

fn fill_random(dst: []u8) void {
    if (prng == null) prng = std.Random.DefaultPrng.init(cpu.read_tsc());
    prng.?.random().bytes(dst);
}

pub const SysvLayout = struct {
    const Self = @This();

    /// total size in bytes of argv/envp strings and the AT_RANDOM block
    strs_len: usize,
    /// argc, the argv pointers, their NULL, the envp pointers and their NULL
    n_words: usize,
    auxv_len: usize,

    pub fn init(argv: []const [:0]const u8, envp: []const [:0]const u8, image: elf.Image) Self {
        var self: Self = .{
            .strs_len = random_len,
            .n_words = 1 + argv.len + 1 + envp.len + 1,
            .auxv_len = auxv_count(image, argv.len),
        };
        for (argv) |arg| self.strs_len += arg.len + 1;
        for (envp) |env| self.strs_len += env.len + 1;
        return self;
    }

    fn auxv_count(image: elf.Image, argv_len: usize) usize {
        // AT_ENTRY, AT_PAGESZ, AT_RANDOM, AT_SECURE, AT_NULL
        var n: usize = 5;
        if (image.phdr_vaddr != 0) n += 3;
        if (argv_len != 0) n += 1;
        return n;
    }

    /// Upper bound on the bytes the entry block occupies below `stack_top`. The trailing
    /// 16 bytes cover the padding that aligning the final stack pointer may consume.
    pub fn size(self: *const Self) usize {
        return self.strs_len + self.n_words * @sizeOf(usize) +
            self.auxv_len * @sizeOf(std.elf.Auxv) + 16;
    }
};

/// refering to the sysv i386 ABI:
/// - If the AT_PHDR entry is present, entries of types AT_PHENT, AT_PHNUM, and AT_ENTRY must also be present.
/// Note: That is an implication, not an equivalence: AT_ENTRY alone would be legal, and still informative for
/// an image with no program header table.
///
/// `execfn` is 0 when there is no argv[0] to point at.
fn build_auxv(
    buf: *[max_auxv]std.elf.Auxv,
    image: elf.Image,
    random: usize,
    execfn: usize,
) []std.elf.Auxv {
    var len: usize = 0;

    if (image.phdr_vaddr != 0) {
        buf[0] = .{ .a_type = std.elf.AT_PHDR, .a_un = .{ .a_val = image.phdr_vaddr } };
        buf[1] = .{ .a_type = std.elf.AT_PHENT, .a_un = .{ .a_val = image.phentsize } };
        buf[2] = .{ .a_type = std.elf.AT_PHNUM, .a_un = .{ .a_val = image.phnum } };
        len += 3;
    }
    if (execfn != 0) {
        buf[len] = .{ .a_type = std.elf.AT_EXECFN, .a_un = .{ .a_val = execfn } };
        len += 1;
    }
    buf[len] = .{ .a_type = std.elf.AT_ENTRY, .a_un = .{ .a_val = image.entry } };
    buf[len + 1] = .{ .a_type = std.elf.AT_PAGESZ, .a_un = .{ .a_val = paging.page_size } };
    buf[len + 2] = .{ .a_type = std.elf.AT_RANDOM, .a_un = .{ .a_val = random } };
    // Nothing raises privileges on exec yet, so the image is never privileged.
    buf[len + 3] = .{ .a_type = std.elf.AT_SECURE, .a_un = .{ .a_val = 0 } };
    buf[len + 4] = .{ .a_type = std.elf.AT_NULL, .a_un = .{ .a_val = 0 } };
    return buf[0 .. len + 5];
}

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
    // argv[0] is the first string pushed, so it is also what AT_EXECFN points at.
    const execfn = if (argv.len != 0) strs_base else 0;
    builder.push_vector(argv);
    builder.push_vector(envp);
    std.debug.assert(builder.count == layout.n_words);

    // The entropy block sits above the strings, at the very top of the stack.
    const random = builder.str_next;
    fill_random(@as([*]u8, @ptrFromInt(random))[0..random_len]);
    std.debug.assert(random + random_len == stack_top);

    var auxv_buf: [max_auxv]std.elf.Auxv = undefined;
    const auxv = std.mem.sliceAsBytes(build_auxv(&auxv_buf, image, random, execfn));
    std.debug.assert(auxv.len == layout.auxv_len * @sizeOf(std.elf.Auxv));

    const auxv_at = stack_ptr + builder.count * @sizeOf(usize);
    std.debug.assert(auxv_at + auxv.len <= strs_base);

    const dst: [*]u8 = @ptrFromInt(auxv_at);
    @memcpy(dst[0..auxv.len], auxv);

    return stack_ptr;
}
