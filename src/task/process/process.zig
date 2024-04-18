const memory = @import("../../memory.zig");
const Cache = @import("../../memory/object_allocators/slab/cache.zig").Cache;

pub const TaskControlBlock = extern struct {
    esp: u32,
    prev: *TaskUnion,
    next: *TaskUnion,
};

pub const TaskUnion = extern union {
    task: TaskControlBlock,
    stack: [2048]u8,

    const Self = @This();

    pub var cache: ?*Cache = null;

    pub fn init_cache() !void {
        cache = try memory.globalCache.create(
            "kernel_task",
            memory.directPageAllocator.page_allocator(),
            @sizeOf(TaskUnion),
            4,
        );
    }

    pub fn create() !*Self {
        if (cache) |c| {
            return @ptrCast(c.alloc_one);
        } else {
            @panic("kernel_task cache is not initialized");
        }
    }

    pub fn init(esp: u32, prev: *TaskUnion, next: *TaskUnion) Self {
        return TaskUnion{ .task = .{
            .esp = esp,
            .prev = prev,
            .next = next,
        } };
    }
};

pub fn switch_to_task(prev: *TaskUnion, next: *TaskUnion) void {
    asm volatile (
        \\push %ebx
        \\push %esi
        \\push %edi
        \\push %ebp
    );
    prev.task.esp = asm volatile ("mov %esp, %eax"
        : [_] "={eax}" (-> u32),
    );
    asm volatile ("mov %eax, %esp"
        :
        : [_] "{eax}" (next.task.esp),
    );
    asm volatile (
        \\pop %ebp
        \\pop %edi
        \\pop %esi
        \\pop %ebx
    );
}

pub fn clone(function: *const fn () void, stack: *void) void {
    asm volatile (
        \\mov %eax, %esp
        \\push %ebx
        \\ret
        :
        : [_] "{eax}" (stack),
          [_] "{ebx}" (function),
    );
}
