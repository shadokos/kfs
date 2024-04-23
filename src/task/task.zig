const memory = @import("../memory.zig");
const task_set = @import("task_set.zig");
const Cache = @import("../memory/object_allocators/slab/cache.zig").Cache;
const scheduler = @import("scheduler.zig");

const logger = @import("../ft/ft.zig").log.scoped(.task);
pub const TaskDescriptor = extern struct {
    pid: Pid,
    esp: u32 = undefined,
    prev: *TaskDescriptor = undefined,
    next: *TaskDescriptor = undefined,

    pub const Pid = u32;
};

pub const TaskUnion = extern union {
    task: TaskDescriptor,
    stack: [2048]u8,

    const Self = @This();

    pub var cache: *Cache = undefined;

    pub fn init_cache() !void {
        cache = try memory.globalCache.create(
            "kernel_task",
            memory.directPageAllocator.page_allocator(),
            @sizeOf(TaskUnion),
            4,
        );
    }

    pub fn init(esp: u32, prev: *TaskUnion, next: *TaskUnion) Self {
        return TaskUnion{ .task = .{
            .esp = esp,
            .prev = prev,
            .next = next,
        } };
    }
};

pub fn switch_to_task(prev: *TaskDescriptor, next: *TaskDescriptor) void {
    asm volatile ("pushaw");
    prev.esp = asm volatile ("mov %esp, %eax"
        : [_] "={eax}" (-> u32),
    );
    asm volatile ("mov %eax, %esp"
        :
        : [_] "{eax}" (next.esp),
    );
    asm volatile ("popaw");
}

pub fn spawn(function: *const fn () void) !*TaskDescriptor {
    const descriptor = try task_set.create_task();
    const taskUnion: *TaskUnion = @fieldParentPtr("task", descriptor);
    scheduler.add_task(descriptor);

    var is_parent: bool = false;
    scheduler.checkpoint();
    if (is_parent) {
        return descriptor;
    } else {
        is_parent = true;
        scheduler.set_current_task(descriptor);
        asm volatile (
            \\mov %eax, %esp
            \\push %ebx
            \\ret
            :
            : [_] "{eax}" (@as(usize, @intFromPtr(&taskUnion.stack)) + taskUnion.stack.len),
              [_] "{ebx}" (function),
        );
        unreachable;
    }
}
