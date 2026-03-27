// ACPI resource descriptor parser for _CRS/_PRS buffers.
//
// Decodes small and large resource descriptors (ACPI spec §6.4)
// into a flat ResourceList without heap allocation.

pub const MAX_RESOURCES = 16;
pub const MAX_EXT_IRQS = 8;

pub const Resource = union(enum) {
    irq: IrqResource,
    extended_irq: ExtIrqResource,
    io_port: IoPortResource,
    fixed_io: FixedIoResource,
    memory32_fixed: Memory32FixedResource,
    dma: DmaResource,
    address_space: AddressSpaceResource,
};

pub const IrqResource = struct {
    irq_mask: u16,
};

pub const ExtIrqResource = struct {
    consumer: bool,
    edge_triggered: bool,
    active_low: bool,
    shared: bool,
    irq_count: u8,
    irqs: [MAX_EXT_IRQS]u32,
};

pub const IoPortResource = struct {
    decode_16: bool,
    min_base: u16,
    max_base: u16,
    alignment: u8,
    range_length: u8,
};

pub const Memory32FixedResource = struct {
    read_write: bool,
    base_address: u32,
    range_length: u32,
};

pub const DmaResource = struct {
    channel_mask: u8,
    type_flags: u8,
};

pub const FixedIoResource = struct {
    base_address: u16,
    range_length: u8,
};

/// Unified descriptor for DWord (0x07), Word (0x08), and QWord (0x0A)
/// Address Space resources (ACPI §6.4.3.5).
pub const AddressSpaceResource = struct {
    resource_type: ResourceType,
    general_flags: u8,
    type_flags: u8,
    granularity: u64,
    range_min: u64,
    range_max: u64,
    translation_offset: u64,
    address_length: u64,

    pub const ResourceType = enum(u8) {
        memory = 0,
        io = 1,
        bus_number = 2,
        _,
    };

    pub fn is_subtractive(self: AddressSpaceResource) bool {
        return self.general_flags & 0x02 != 0;
    }
};

pub const ResourceList = struct {
    items: [MAX_RESOURCES]Resource = undefined,
    count: usize = 0,

    fn add(self: *ResourceList, res: Resource) void {
        if (self.count < MAX_RESOURCES) {
            self.items[self.count] = res;
            self.count += 1;
        }
    }
};

/// Parse an ACPI resource descriptor buffer (_CRS/_PRS result).
pub fn parse(data: []const u8) ResourceList {
    var result = ResourceList{};
    var pos: usize = 0;

    while (pos < data.len) {
        const tag = data[pos];

        if (tag & 0x80 == 0) {
            // Small resource descriptor
            const stype = (tag >> 3) & 0x0F;
            const slen: usize = tag & 0x07;
            pos += 1;
            if (pos + slen > data.len) break;
            const body = data[pos..][0..slen];

            switch (stype) {
                0x04 => { // IRQ descriptor (ACPI §6.4.2.1)
                    if (slen >= 2) {
                        result.add(.{ .irq = .{
                            .irq_mask = read_u16(body, 0),
                        } });
                    }
                },
                0x05 => { // DMA descriptor (ACPI §6.4.2.2)
                    if (slen >= 2) {
                        result.add(.{ .dma = .{
                            .channel_mask = body[0],
                            .type_flags = body[1],
                        } });
                    }
                },
                0x08 => { // I/O port descriptor (ACPI §6.4.2.5)
                    if (slen >= 7) {
                        result.add(.{ .io_port = .{
                            .decode_16 = body[0] & 1 != 0,
                            .min_base = read_u16(body, 1),
                            .max_base = read_u16(body, 3),
                            .alignment = body[5],
                            .range_length = body[6],
                        } });
                    }
                },
                0x09 => { // Fixed I/O port descriptor (ACPI §6.4.2.6)
                    if (slen >= 3) {
                        result.add(.{ .fixed_io = .{
                            .base_address = read_u16(body, 0),
                            .range_length = body[2],
                        } });
                    }
                },
                0x0F => break, // End tag
                else => {},
            }
            pos += slen;
        } else {
            // Large resource descriptor
            pos += 1;
            if (pos + 2 > data.len) break;
            const llen: usize = read_u16(data, pos);
            pos += 2;
            if (pos + llen > data.len) break;
            const body = data[pos..][0..llen];
            const ltype = tag & 0x7F;

            switch (ltype) {
                0x06 => { // Memory32Fixed (ACPI §6.4.3.4)
                    if (llen >= 9) {
                        result.add(.{ .memory32_fixed = .{
                            .read_write = body[0] & 1 != 0,
                            .base_address = read_u32(body, 1),
                            .range_length = read_u32(body, 5),
                        } });
                    }
                },
                0x07 => { // DWord Address Space (ACPI §6.4.3.5.2)
                    if (llen >= 23) {
                        result.add(.{ .address_space = .{
                            .resource_type = @enumFromInt(body[0]),
                            .general_flags = body[1],
                            .type_flags = body[2],
                            .granularity = read_u32(body, 3),
                            .range_min = read_u32(body, 7),
                            .range_max = read_u32(body, 11),
                            .translation_offset = read_u32(body, 15),
                            .address_length = read_u32(body, 19),
                        } });
                    }
                },
                0x08 => { // Word Address Space (ACPI §6.4.3.5.3)
                    if (llen >= 13) {
                        result.add(.{ .address_space = .{
                            .resource_type = @enumFromInt(body[0]),
                            .general_flags = body[1],
                            .type_flags = body[2],
                            .granularity = read_u16(body, 3),
                            .range_min = read_u16(body, 5),
                            .range_max = read_u16(body, 7),
                            .translation_offset = read_u16(body, 9),
                            .address_length = read_u16(body, 11),
                        } });
                    }
                },
                0x09 => { // Extended IRQ (ACPI §6.4.3.6)
                    if (llen >= 2) {
                        const flags = body[0];
                        const count = body[1];
                        var irqs: [MAX_EXT_IRQS]u32 = .{0} ** MAX_EXT_IRQS;
                        const n = @min(count, MAX_EXT_IRQS);
                        for (0..n) |i| {
                            if (2 + i * 4 + 4 <= llen) {
                                irqs[i] = read_u32(body, 2 + i * 4);
                            }
                        }
                        result.add(.{ .extended_irq = .{
                            .consumer = flags & 1 != 0,
                            .edge_triggered = flags & 2 != 0,
                            .active_low = flags & 4 != 0,
                            .shared = flags & 8 != 0,
                            .irq_count = n,
                            .irqs = irqs,
                        } });
                    }
                },
                0x0A => { // QWord Address Space (ACPI §6.4.3.5.1)
                    if (llen >= 43) {
                        result.add(.{ .address_space = .{
                            .resource_type = @enumFromInt(body[0]),
                            .general_flags = body[1],
                            .type_flags = body[2],
                            .granularity = read_u64(body, 3),
                            .range_min = read_u64(body, 11),
                            .range_max = read_u64(body, 19),
                            .translation_offset = read_u64(body, 27),
                            .address_length = read_u64(body, 35),
                        } });
                    }
                },
                else => {},
            }
            pos += llen;
        }
    }
    return result;
}

/// Print a resource list to a writer.
pub fn print(list: *const ResourceList, writer: anytype) void {
    if (list.count == 0) {
        writer.print("  (no resources)\n", .{}) catch {};
        return;
    }
    for (list.items[0..list.count]) |res| {
        switch (res) {
            .irq => |r| {
                writer.print("  IRQ: mask=0x{x:0>4}", .{r.irq_mask}) catch {};
                print_irq_bits(r.irq_mask, writer);
                writer.print("\n", .{}) catch {};
            },
            .extended_irq => |r| {
                writer.print("  ExtIRQ: {s} {s} {s}", .{
                    if (r.edge_triggered) @as([]const u8, "edge") else "level",
                    if (r.active_low) @as([]const u8, "low") else "high",
                    if (r.shared) @as([]const u8, "shared") else "exclusive",
                }) catch {};
                for (r.irqs[0..r.irq_count]) |irq| {
                    writer.print(" {d}", .{irq}) catch {};
                }
                writer.print("\n", .{}) catch {};
            },
            .io_port => |r| {
                writer.print("  I/O: 0x{x:0>4}-0x{x:0>4} len={d} align={d}\n", .{
                    r.min_base, r.max_base, r.range_length, r.alignment,
                }) catch {};
            },
            .memory32_fixed => |r| {
                writer.print("  Mem32: 0x{x:0>8} len=0x{x} {s}\n", .{
                    r.base_address,
                    r.range_length,
                    if (r.read_write) @as([]const u8, "RW") else "RO",
                }) catch {};
            },
            .dma => |r| {
                writer.print("  DMA: channels=0x{x:0>2} flags=0x{x:0>2}\n", .{
                    r.channel_mask, r.type_flags,
                }) catch {};
            },
            .fixed_io => |r| {
                writer.print("  FixedIO: 0x{x:0>4} len={d}\n", .{
                    r.base_address, r.range_length,
                }) catch {};
            },
            .address_space => |r| {
                const kind: []const u8 = switch (r.resource_type) {
                    .memory => "Mem",
                    .io => "IO",
                    .bus_number => "Bus",
                    _ => "???",
                };
                writer.print("  {s}: 0x{x}-0x{x} len=0x{x}", .{
                    kind, r.range_min, r.range_max, r.address_length,
                }) catch {};
                if (r.translation_offset != 0) {
                    writer.print(" tra=0x{x}", .{r.translation_offset}) catch {};
                }
                if (r.is_subtractive()) {
                    writer.print(" [sub]", .{}) catch {};
                }
                writer.print("\n", .{}) catch {};
            },
        }
    }
}

fn print_irq_bits(mask: u16, writer: anytype) void {
    writer.print(" (", .{}) catch {};
    var first = true;
    for (0..16) |i| {
        if (mask & (@as(u16, 1) << @intCast(i)) != 0) {
            if (!first) writer.print(",", .{}) catch {};
            writer.print("{d}", .{i}) catch {};
            first = false;
        }
    }
    writer.print(")", .{}) catch {};
}

fn read_u16(data: []const u8, off: usize) u16 {
    return @as(u16, data[off]) | (@as(u16, data[off + 1]) << 8);
}

fn read_u32(data: []const u8, off: usize) u32 {
    return @as(u32, data[off]) |
        (@as(u32, data[off + 1]) << 8) |
        (@as(u32, data[off + 2]) << 16) |
        (@as(u32, data[off + 3]) << 24);
}

fn read_u64(data: []const u8, off: usize) u64 {
    return @as(u64, read_u32(data, off)) |
        (@as(u64, read_u32(data, off + 4)) << 32);
}
