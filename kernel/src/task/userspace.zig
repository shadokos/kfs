const std = @import("std");
const gdt = @import("../gdt.zig");
const cpu = @import("../cpu.zig");
const elf = @import("elf.zig");
const sysv = @import("sysv.zig");
const memory = @import("../memory.zig");
const VirtualSpace = @import("../memory/virtual_space.zig").VirtualSpace;
const paging = @import("../memory/paging.zig");
const interrupts = @import("../interrupts.zig");
const RegionSet = @import("../memory/region_set.zig").RegionSet;
const regions = @import("../memory/regions.zig");

fn create_stack(vm: *VirtualSpace, size: usize) paging.VirtualPagePtr {
    const region = RegionSet.create_region() catch @panic("cannot map userspace");
    errdefer RegionSet.destroy_region(region) catch unreachable;

    region.flags = .{
        .read = true,
        .write = true,
        .may_read = true,
        .may_write = true,
    };

    regions.VirtuallyContiguousRegion.init(region, .{
        .private = true,
    });

    vm.add_region(region, size) catch @panic("cannot map userspace");

    return @ptrFromInt(region.begin * paging.page_size);
}

const stack_pages: usize = 8; // todo: get this from config (static or dynamic)

pub const PreparedEntry = struct { vm: *VirtualSpace, ip: usize, sp: usize };

pub fn prepare_entry(
    vm: *VirtualSpace,
    image: elf.Image,
    argv: []const [:0]const u8,
    envp: []const [:0]const u8,
) PreparedEntry {
    const sysv_block_size = sysv.SysvLayout.init(argv, envp, image).size();
    std.debug.assert(sysv_block_size <= sysv.arg_max);

    const block_pages = std.math.divCeil(usize, sysv_block_size, paging.page_size) catch unreachable;
    const total_pages = stack_pages + block_pages;

    const stack = create_stack(vm, total_pages);
    const stack_top = @as(usize, @intFromPtr(stack)) + (paging.page_size * total_pages);

    return PreparedEntry{
        .vm = vm,
        .ip = image.entry,
        .sp = sysv.build_sysv_stack(stack_top, argv, envp, image),
    };
}

pub fn iret_to(entry: PreparedEntry) noreturn {
    entry.vm.transfer();
    const frame = interrupts.InterruptFrame{
        .edi = 0,
        .esi = 0,
        .ebp = 0,
        .edx = 0,
        .ecx = 0,
        .ebx = 0,
        .eax = 0,
        .code = 0,
        .iret = .{
            .ip = entry.ip,
            .cs = .{ .index = 4, .table = .GDT, .privilege = .User },
            .flags = @bitCast(cpu.EFlags{ .interrupt_enable = true }),
            .sp = entry.sp,
            .ss = .{ .index = 6, .table = .GDT, .privilege = .User },
        },
    };
    interrupts.ret_from_interrupt(&frame);
}

/// Drop to ring 3 on 'image' inside 'vm'. The caller must have mapped everything the
/// image needs beforehand, nothing is loaded here.
pub fn enter_userspace(
    vm: *VirtualSpace,
    image: elf.Image,
    argv: []const [:0]const u8,
    envp: []const [:0]const u8,
) noreturn {
    iret_to(prepare_entry(vm, image, argv, envp));
}

/// Map the .userspace section into 'vm' so ring 3 can run the userland_* entry points.
/// Only needed because these demos are kernel-linked code and not loadable images.
pub fn map_userspace(vm: *VirtualSpace) void {
    const up_start = std.mem.alignBackward(u32, @intFromPtr(@extern(*u8, .{ .name = "userspace_start" })), 4096);
    const up_end = std.mem.alignForward(u32, @intFromPtr(@extern(*u8, .{ .name = "userspace_end" })), 4096);

    const region = RegionSet.create_region() catch @panic("cannot map userspace");
    errdefer RegionSet.destroy_region(region) catch unreachable;

    region.flags = .{
        .read = true,
        .write = true,
        .may_read = true,
        .may_write = true,
    };

    regions.PhysicalMapping.init(region, 0);

    vm.add_region_at(
        region,
        up_start / paging.page_size,
        (up_end - up_start) / paging.page_size,
        true,
    ) catch @panic("cannot map userspace");
}
