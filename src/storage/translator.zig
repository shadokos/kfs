// src/storage/translator.zig
const std = @import("std");
const BlockError = @import("block_device.zig").BlockError;
const STANDARD_BLOCK_SIZE = @import("block_device.zig").STANDARD_BLOCK_SIZE;
const logger = std.log.scoped(.translator.zig);

const allocator = @import("../memory.zig").bigAlloc.allocator();

pub const PhysicalRange = struct {
    physical_start: u32,
    physical_count: u32,
};

/// Function type for performing physical I/O operations
pub const PhysicalIOFn = *const fn (
    context: *anyopaque,
    physical_block: u32,
    count: u32,
    buffer: []u8,
    is_write: bool,
) BlockError!void;

/// Translation operation result
pub const TranslationOp = struct {
    physical_start: u32,
    physical_count: u32,
    buffer_offset: usize,
    buffer_size: usize,
    needs_rmw: bool, // Read-modify-write required
    rmw_offset: usize, // Offset within physical block for partial operations
    rmw_size: usize, // Size of data to copy for partial operations
};

/// Generic block translator interface
pub const BlockTranslator = struct {
    vtable: *const VTable,
    context: *anyopaque,
    physical_block_size: u32,
    logical_block_size: u32,
    temp_buffer: ?[]align(16) u8,

    const VTable = struct {
        /// Convert logical block address to physical
        logicalToPhysical: *const fn (ctx: *anyopaque, logical: u32) u32,

        /// Calculate how many physical blocks are needed for logical range
        calculatePhysicalRange: *const fn (
            ctx: *anyopaque,
            logical_start: u32,
            logical_count: u32,
        ) PhysicalRange,

        /// Plan translation operations for a logical I/O request
        planOperations: *const fn (
            ctx: *anyopaque,
            logical_start: u32,
            logical_count: u32,
            ops: []TranslationOp,
        ) u32,

        /// Destroy the translator
        deinit: *const fn (ctx: *anyopaque) void,
    };

    const Self = @This();

    /// Read logical blocks using physical I/O
    pub fn read(
        self: *Self,
        logical_start: u32,
        logical_count: u32,
        buffer: []u8,
        physical_io: PhysicalIOFn,
        io_context: *anyopaque,
    ) BlockError!void {
        if (buffer.len < logical_count * self.logical_block_size) {
            return BlockError.BufferTooSmall;
        }

        // For simple 1:1 mapping, use direct path
        if (self.physical_block_size == self.logical_block_size) {
            return physical_io(io_context, logical_start, logical_count, buffer, false);
        }

        // Complex translation required
        var ops_buffer: [16]TranslationOp = undefined;
        const ops_count = self.vtable.planOperations(
            self.context,
            logical_start,
            logical_count,
            &ops_buffer,
        );

        var buffer_offset: usize = 0;

        for (ops_buffer[0..ops_count]) |op| {
            if (op.needs_rmw) {
                // Read-modify-write operation for partial blocks
                try self.performRMWRead(op, buffer, &buffer_offset, physical_io, io_context);
            } else {
                // Direct read operation
                try physical_io(
                    io_context,
                    op.physical_start,
                    op.physical_count,
                    buffer[buffer_offset .. buffer_offset + op.buffer_size],
                    false,
                );
                buffer_offset += op.buffer_size;
            }
        }
    }

    /// Write logical blocks using physical I/O
    pub fn write(
        self: *Self,
        logical_start: u32,
        logical_count: u32,
        buffer: []const u8,
        physical_io: PhysicalIOFn,
        io_context: *anyopaque,
    ) BlockError!void {
        if (buffer.len < logical_count * self.logical_block_size) {
            return BlockError.BufferTooSmall;
        }

        // For simple 1:1 mapping, use direct path
        if (self.physical_block_size == self.logical_block_size) {
            // Cast const buffer to mutable for the function signature
            const mutable_buffer: []u8 = @constCast(buffer);
            return physical_io(io_context, logical_start, logical_count, mutable_buffer, true);
        }

        // Complex translation required
        var ops_buffer: [16]TranslationOp = undefined;
        const ops_count = self.vtable.planOperations(
            self.context,
            logical_start,
            logical_count,
            &ops_buffer,
        );

        var buffer_offset: usize = 0;

        for (ops_buffer[0..ops_count]) |op| {
            if (op.needs_rmw) {
                // Read-modify-write operation for partial blocks
                try self.performRMWWrite(op, buffer, &buffer_offset, physical_io, io_context);
            } else {
                // Direct write operation
                const mutable_buffer: []u8 = @constCast(buffer);
                try physical_io(
                    io_context,
                    op.physical_start,
                    op.physical_count,
                    mutable_buffer[buffer_offset .. buffer_offset + op.buffer_size],
                    true,
                );
                buffer_offset += op.buffer_size;
            }
        }
    }

    fn performRMWRead(
        self: *Self,
        op: TranslationOp,
        buffer: []u8,
        buffer_offset: *usize,
        physical_io: PhysicalIOFn,
        io_context: *anyopaque,
    ) BlockError!void {
        const temp_buffer = self.temp_buffer orelse return BlockError.OutOfMemory;

        // Read the physical block
        try physical_io(io_context, op.physical_start, 1, temp_buffer, false);

        // Copy the relevant portion to the output buffer
        @memcpy(
            buffer[buffer_offset.* .. buffer_offset.* + op.rmw_size],
            temp_buffer[op.rmw_offset .. op.rmw_offset + op.rmw_size],
        );

        buffer_offset.* += op.rmw_size;
    }

    fn performRMWWrite(
        self: *Self,
        op: TranslationOp,
        buffer: []const u8,
        buffer_offset: *usize,
        physical_io: PhysicalIOFn,
        io_context: *anyopaque,
    ) BlockError!void {
        const temp_buffer = self.temp_buffer orelse return BlockError.OutOfMemory;

        // Read the existing physical block
        try physical_io(io_context, op.physical_start, 1, temp_buffer, false);

        // Modify the relevant portion
        @memcpy(
            temp_buffer[op.rmw_offset .. op.rmw_offset + op.rmw_size],
            buffer[buffer_offset.* .. buffer_offset.* + op.rmw_size],
        );

        // Write back the modified block
        try physical_io(io_context, op.physical_start, 1, temp_buffer, true);

        buffer_offset.* += op.rmw_size;
    }

    pub fn deinit(self: *Self) void {
        if (self.temp_buffer) |temp| {
            allocator.free(temp);
        }
        self.vtable.deinit(self.context);
    }
};

/// Direct 1:1 translator (logical == physical)
pub const DirectTranslator = struct {
    base: BlockTranslator,

    const vtable = BlockTranslator.VTable{
        .logicalToPhysical = logicalToPhysical,
        .calculatePhysicalRange = calculatePhysicalRange,
        .planOperations = planOperations,
        .deinit = deinitTranslator,
    };

    pub fn create(block_size: u32) !*DirectTranslator {
        const translator = try allocator.create(DirectTranslator);
        translator.* = .{
            .base = .{
                .vtable = &vtable,
                .context = translator,
                .physical_block_size = block_size,
                .logical_block_size = block_size,
                .temp_buffer = null,
            },
        };
        return translator;
    }

    fn logicalToPhysical(ctx: *anyopaque, logical: u32) u32 {
        _ = ctx;
        return logical;
    }

    fn calculatePhysicalRange(
        ctx: *anyopaque,
        logical_start: u32,
        logical_count: u32,
    ) PhysicalRange {
        _ = ctx;
        return .{
            .physical_start = logical_start,
            .physical_count = logical_count,
        };
    }

    fn planOperations(
        ctx: *anyopaque,
        logical_start: u32,
        logical_count: u32,
        ops: []TranslationOp,
    ) u32 {
        _ = ctx;

        if (ops.len == 0) return 0;

        ops[0] = .{
            .physical_start = logical_start,
            .physical_count = logical_count,
            .buffer_offset = 0,
            .buffer_size = logical_count * STANDARD_BLOCK_SIZE,
            .needs_rmw = false,
            .rmw_offset = 0,
            .rmw_size = 0,
        };

        return 1;
    }

    fn deinitTranslator(ctx: *anyopaque) void {
        const self: *DirectTranslator = @ptrCast(@alignCast(ctx));
        allocator.destroy(self);
    }
};

/// Scaled translator (N logical blocks per physical block)
pub const ScaledTranslator = struct {
    base: BlockTranslator,
    scale_shift: u5, // How many logical blocks per physical (as power of 2)
    logical_per_physical: u32,

    const vtable = BlockTranslator.VTable{
        .logicalToPhysical = logicalToPhysical,
        .calculatePhysicalRange = calculatePhysicalRange,
        .planOperations = planOperations,
        .deinit = deinitTranslator,
    };

    pub fn create(physical_block_size: u32) !*ScaledTranslator {
        if (physical_block_size < STANDARD_BLOCK_SIZE or
            physical_block_size % STANDARD_BLOCK_SIZE != 0)
        {
            return BlockError.InvalidOperation;
        }

        const scale = physical_block_size / STANDARD_BLOCK_SIZE;
        const scale_shift = calculateShift(scale);

        const translator = try allocator.create(ScaledTranslator);
        errdefer allocator.destroy(translator);

        const temp_buffer = try allocator.alignedAlloc(u8, 16, physical_block_size);
        errdefer allocator.free(temp_buffer);

        translator.* = .{
            .base = .{
                .vtable = &vtable,
                .context = translator,
                .physical_block_size = physical_block_size,
                .logical_block_size = STANDARD_BLOCK_SIZE,
                .temp_buffer = temp_buffer,
            },
            .scale_shift = scale_shift,
            .logical_per_physical = scale,
        };

        return translator;
    }

    fn calculateShift(scale: u32) u5 {
        var s = scale;
        var shift: u5 = 0;
        while (s > 1) : (shift += 1) {
            s >>= 1;
        }
        return shift;
    }

    fn logicalToPhysical(ctx: *anyopaque, logical: u32) u32 {
        const self: *ScaledTranslator = @ptrCast(@alignCast(ctx));
        return logical >> self.scale_shift;
    }

    fn calculatePhysicalRange(
        ctx: *anyopaque,
        logical_start: u32,
        logical_count: u32,
    ) PhysicalRange {
        const self: *ScaledTranslator = @ptrCast(@alignCast(ctx));

        const first_physical = logical_start >> self.scale_shift;
        const last_logical = logical_start + logical_count - 1;
        const last_physical = last_logical >> self.scale_shift;

        return .{
            .physical_start = first_physical,
            .physical_count = @truncate(last_physical - first_physical + 1),
        };
    }

    fn planOperations(
        ctx: *anyopaque,
        logical_start: u32,
        logical_count: u32,
        ops: []TranslationOp,
    ) u32 {
        const self: *ScaledTranslator = @ptrCast(@alignCast(ctx));

        if (ops.len == 0) return 0;

        const mask = self.logical_per_physical - 1;
        const first_physical = logical_start >> self.scale_shift;
        const last_logical = logical_start + logical_count - 1;
        const last_physical = last_logical >> self.scale_shift;
        const physical_count = last_physical - first_physical + 1;

        const first_offset = (logical_start & mask) * STANDARD_BLOCK_SIZE;
        const last_end = ((last_logical & mask) + 1) * STANDARD_BLOCK_SIZE;

        var op_count: u32 = 0;
        var buffer_offset: usize = 0;

        // First physical block (may be partial)
        if (first_offset != 0 or (physical_count == 1 and last_end != self.base.physical_block_size)) {
            if (op_count >= ops.len) return op_count;

            const copy_end = if (physical_count == 1) last_end else self.base.physical_block_size;
            const copy_size = copy_end - first_offset;

            ops[op_count] = .{
                .physical_start = first_physical,
                .physical_count = 1,
                .buffer_offset = buffer_offset,
                .buffer_size = copy_size,
                .needs_rmw = true,
                .rmw_offset = first_offset,
                .rmw_size = copy_size,
            };

            buffer_offset += copy_size;
            op_count += 1;

            if (physical_count == 1) return op_count;
        }

        // Middle physical blocks (complete)
        const middle_start = if (first_offset == 0) first_physical else first_physical + 1;
        const middle_count = if (last_end == self.base.physical_block_size)
            physical_count - @intFromBool(first_offset != 0)
        else
            physical_count - @intFromBool(first_offset != 0) - 1;

        if (middle_count > 0) {
            if (op_count >= ops.len) return op_count;

            ops[op_count] = .{
                .physical_start = middle_start,
                .physical_count = middle_count,
                .buffer_offset = buffer_offset,
                .buffer_size = middle_count * self.base.physical_block_size,
                .needs_rmw = false,
                .rmw_offset = 0,
                .rmw_size = 0,
            };

            buffer_offset += middle_count * self.base.physical_block_size;
            op_count += 1;
        }

        // Last physical block (may be partial)
        if (physical_count > 1 and last_end != self.base.physical_block_size and first_offset == 0) {
            if (op_count >= ops.len) return op_count;

            ops[op_count] = .{
                .physical_start = last_physical,
                .physical_count = 1,
                .buffer_offset = buffer_offset,
                .buffer_size = last_end,
                .needs_rmw = true,
                .rmw_offset = 0,
                .rmw_size = last_end,
            };

            op_count += 1;
        }

        return op_count;
    }

    fn deinitTranslator(ctx: *anyopaque) void {
        const self: *ScaledTranslator = @ptrCast(@alignCast(ctx));
        allocator.destroy(self);
    }
};

/// Create appropriate translator for given block sizes
pub fn createTranslator(physical_block_size: u32) !*BlockTranslator {
    if (physical_block_size == STANDARD_BLOCK_SIZE) {
        const direct = try DirectTranslator.create(physical_block_size);
        return &direct.base;
    } else {
        const scaled = try ScaledTranslator.create(physical_block_size);
        return &scaled.base;
    }
}
