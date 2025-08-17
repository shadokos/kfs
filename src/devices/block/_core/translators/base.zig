const core = @import("../../core.zig");
const types = core.types;
const STANDARD_BLOCK_SIZE = core.STANDARD_BLOCK_SIZE;

const BlockError = types.BlockError;
const PhysicalIOFn = types.PhysicalIOFn;

const PhysicalRange = core.translator.PhysicalRange;
const TranslationOp = core.translator.TranslationOp;
const VTable = core.translator.VTable;

const allocator = @import("../../../../memory.zig").bigAlloc.allocator();

vtable: *const VTable,
context: *anyopaque,
physical_block_size: u32,
logical_block_size: u32,
temp_buffer: ?[]align(16) u8,

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
    self.vtable.deinit(self.context);
}
