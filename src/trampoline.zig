const paging = @import("memory/paging.zig");
const ft = @import("ft/ft.zig");
const cpu = @import("cpu.zig");

pub const kernel_size = 0x10_000_000 + paging.direct_zone_size;

const page_count = ft.math.divCeil(
    comptime_int,
    kernel_size,
    paging.page_size,
) catch unreachable;

pub const table_count linksection(".bootstrap") = ft.math.divCeil(
    comptime_int,
    page_count,
    paging.page_table_size,
) catch unreachable;

fn get_page_tables() [table_count][1024]paging.page_table_entry {
    var ret: [table_count][1024]paging.page_table_entry = .{.{paging.page_table_entry{}} ** 1024} ** table_count;
    @setEvalBranchQuota(2000000);
    for (0..page_count) |i| {
        const table = i / paging.page_table_size;
        ret[table][i % paging.page_table_size].present = true;
        ret[table][i % paging.page_table_size].writable = true;
        // TODO: remove
        ret[table][i % paging.page_table_size].owner = .User;
        ret[table][i % paging.page_table_size].address_fragment = i;
    }
    return ret;
}

pub export const page_tables: ([table_count][1024]paging.page_table_entry) align(4096) linksection(".bootstrap") =
    get_page_tables();

pub var page_directory: [1024]paging.page_directory_entry align(4096) linksection(".bootstrap") = undefined;

export fn trampoline_jump() linksection(".bootstrap_code") callconv(.C) void {

    // fill the page directory
    for (0..table_count) |t| {
        page_directory[t] = .{
            .present = true,
            .writable = true,
            // TODO: remove
            .owner = .User,
            .address_fragment = @intCast(t + @intFromPtr(&page_tables) / paging.page_size),
        };
        page_directory[768 + t] = page_directory[t];
    }

    // add one entry for the page directory itself
    @as(*[1024]u32, @ptrCast(&page_directory))[paging.page_dir >> 22] = @intFromPtr(&page_directory) | 3;

    // load the page directory and enable paging
    cpu.set_cr3(@intFromPtr(&page_directory));
    cpu.set_flag(.ProtectedMode);
    cpu.set_flag(.Paging);
}

/// remove identity paging of the kernel
pub fn clean() void {
    @memset(paging.page_dir_ptr[0..(paging.high_half >> 22)], paging.TableEntry{ .not_mapped = .{} });
}
