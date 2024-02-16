const paging = @import("memory/paging.zig");
const ft = @import("ft/ft.zig");

const kernel_size = 0x10_000_000;

const page_count = ft.math.divCeil(comptime_int, kernel_size, paging.page_size) catch unreachable;

pub const table_count linksection(".bootstrap") = ft.math.divCeil(comptime_int, page_count, paging.page_table_size) catch unreachable;

fn get_page_tables() [table_count][1024]paging.page_table_entry {
	var ret : [table_count][1024]paging.page_table_entry = .{.{paging.page_table_entry{}} ** 1024} ** table_count;
	@setEvalBranchQuota(2000000);
	for (0..page_count) |i| {
		const table = i / paging.page_table_size;
		ret[table][i % paging.page_table_size].present = true;
		ret[table][i % paging.page_table_size].writable = true;
		ret[table][i % paging.page_table_size].address_fragment = i;
	}
	return ret;
}

export const page_tables : ([table_count][1024]paging.page_table_entry) align(4096) linksection(".bootstrap")  = get_page_tables();

fn get_page_directory() [1024]paging.page_directory_entry
{
	var ret : [1024]paging.page_directory_entry = .{paging.page_directory_entry{}} ** 1024;
	for (0..table_count) |i| {
		ret[i].present = true;
		ret[i].writable = true;
		ret[i].address_fragment = i;
		ret[768 + i] = ret[i];
	}
	return ret;
}


pub const page_directory : [1024]paging.page_directory_entry align(4096) linksection(".bootstrap") = get_page_directory();

export fn trampoline_jump() linksection(".bootstrap_code") callconv(.C) void {

	asm volatile (
	 \\ loop:
	 \\ cmpl $0, %edx
	 \\ je loop_end
	 \\ dec %edx
	 // \\ mov (%eax, %edx, 4), %ecx
	 \\ movl %edx, %ecx
	 \\ shll $12 , %ecx
	 \\ addl %ebx, %ecx
	 \\ orl $3, %ecx
	 \\ mov %ecx, (%eax, %edx, 4)
	 \\ addl $768, %edx
	 \\ mov %ecx, (%eax, %edx, 4)
	 \\ subl $768, %edx
	 \\ jmp loop
	 \\ loop_end:
	 :
	 : [_] "{eax}" (&page_directory),
	   [_] "{ebx}" (@intFromPtr(&page_tables)),
	   [_] "{edx}" (table_count),
	);

	asm volatile(
	\\ mov %eax, %ecx
	\\ orl $3, %ecx
	\\ mov %ecx, (%eax, %ebx, 4)
	 :
	 : [_] "{eax}" (&page_directory),
	   [_] "{ebx}" (paging.page_dir >> 22),
	);

	asm volatile(
	 \\ mov %eax, %cr3
	 \\ mov %cr0, %eax
	 \\ or $0x80000001, %eax
	 \\ mov %eax, %cr0
	 :
	 : [_] "{eax}" (&page_directory),
	);
}