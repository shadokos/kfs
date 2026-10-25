const core = @import("../block.zig");
const STANDARD_BLOCK_SIZE = core.STANDARD_BLOCK_SIZE;

const BlockError = core.BlockError;
const PhysicalIOFn = core.PhysicalIOFn;

const PhysicalRange = core.translator.PhysicalRange;
const TranslationOp = core.translator.TranslationOp;
const VTable = core.translator.VTable;

vtable: *const VTable,
context: *anyopaque,
sector_size: u32, // Physical sector size of the underlying device
block_size: u32, // Logical block size presented to the user (always 512 bytes)
temp_buffer: ?[]align(16) u8,

// offest and limit will mainly be used for partitioned devices
logical_offset: u32 = 0, // Offset (in logical blocks) from the start of the device
logical_limit: ?u32 = null, // logical block limit (null means no limit)

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
    if (buffer.len < logical_count * self.block_size) {
        return BlockError.BufferTooSmall;
    }

    // Check partition limits
    if (self.logical_limit) |limit| if (logical_start + logical_count > limit)
        return BlockError.OutOfBounds;

    // Add offset to get absolute address
    const absolute_start = logical_start + self.logical_offset;

    // For simple 1:1 mapping, use direct path
    if (self.sector_size == self.block_size) {
        return physical_io(io_context, absolute_start, logical_count, buffer, .Read);
    }

    // Complex translation required
    var ops_buffer: [16]TranslationOp = undefined;
    const ops_count = self.vtable.planOperations(
        self.context,
        absolute_start,
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
                .Read,
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
    if (buffer.len < logical_count * self.block_size) {
        return BlockError.BufferTooSmall;
    }

    // Check partition limits
    if (self.logical_limit) |limit| if (logical_start + logical_count > limit)
        return BlockError.OutOfBounds;

    // Add offset to get absolute address
    const absolute_start = logical_start + self.logical_offset;

    // For simple 1:1 mapping, use direct path
    if (self.sector_size == self.block_size) {
        const mutable_buffer: []u8 = @constCast(buffer);
        return physical_io(io_context, absolute_start, logical_count, mutable_buffer, .Write);
    }

    // Complex translation required
    var ops_buffer: [16]TranslationOp = undefined;
    const ops_count = self.vtable.planOperations(
        self.context,
        absolute_start,
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
                .Write,
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
    try physical_io(io_context, op.physical_start, 1, temp_buffer, .Read);

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
    try physical_io(io_context, op.physical_start, 1, temp_buffer, .Read);

    // Modify the relevant portion
    @memcpy(
        temp_buffer[op.rmw_offset .. op.rmw_offset + op.rmw_size],
        buffer[buffer_offset.* .. buffer_offset.* + op.rmw_size],
    );

    // Write back the modified block
    try physical_io(io_context, op.physical_start, 1, temp_buffer, .Write);

    buffer_offset.* += op.rmw_size;
}

pub fn deinit(self: *Self) void {
    self.vtable.deinit(self.context);
}
