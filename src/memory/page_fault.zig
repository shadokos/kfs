const std = @import("std");
const paging = @import("paging.zig");
const regions = @import("regions.zig");
const Region = regions.Region;
const cpu = @import("../cpu.zig");
const gdt = @import("../gdt.zig");
const mapping = @import("mapping.zig");
const scheduler = @import("../task/scheduler.zig");
const InterruptFrame = @import("../interrupts.zig").InterruptFrame;
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;

const PageFault = struct {
    present: bool,
    type: enum {
        Read,
        Write,
    },
    mode: enum {
        User,
        Kernel,
    },
    faulting_address: paging.VirtualPtr,
    faulting_page: paging.VirtualPagePtr,
    entry: paging.TableEntry,
};

fn page_fault_from_i386(frame: InterruptFrame) PageFault {
    const I386ErrorType = packed struct(u32) {
        present: bool,
        type: enum(u1) {
            Read = 0,
            Write = 1,
        },
        mode: enum(u1) {
            Supervisor = 0,
            User = 1,
        },
        unused: u29 = undefined,
    };
    const error_object: I386ErrorType = @bitCast(frame.code);
    const cr2 = cpu.get_cr2();
    const page: usize = std.mem.alignBackward(usize, cr2, paging.page_size);
    return PageFault{
        .present = error_object.present,
        .type = switch (error_object.type) {
            .Read => .Read,
            .Write => .Write,
        },
        .mode = switch (error_object.mode) {
            .Supervisor => .Kernel,
            .User => .User,
        },
        .faulting_address = @ptrFromInt(cr2),
        .faulting_page = @ptrFromInt(page),
        .entry = mapping.get_entry(@ptrFromInt(page)),
    };
}

fn kernel_page_fault(fault: PageFault) void {
    if (fault.present) {
        unreachable;
    } else if (mapping.is_page_mapped(fault.entry)) {
        @import("regions.zig").make_present(fault.faulting_page) catch |e| {
            std.log.err("PAGE FAULT!\n\tcannot map address 0x{x:0>8}:\n\t{s}", .{
                @intFromPtr(fault.faulting_address),
                @errorName(e),
            });
        };
    } else {
        panic(fault);
    }
}

fn segmentation_fault(task: *TaskDescriptor, fault: PageFault) void {
    task.send_signal(.{
        .si_signo = .{ .valid = .SIGSEGV },
        .si_code = if (fault.present) .SEGV_ACCERR else .SEGV_MAPERR,
        .si_pid = 0,
        .si_addr = fault.faulting_address,
        // todo set more fields of siginfo
    });
}

fn user_page_fault(fault: PageFault) void {
    const task = scheduler.get_current_task();
    const vm = task.vm.?;
    if (fault.present) {
        const region: *Region = vm.find_region(fault.faulting_address) orelse
            @panic("user page with no assiocated region");

        switch (fault.type) {
            .Write => {
                if (region.flags.may_write) {
                    // todo
                    segmentation_fault(task, fault);
                } else {
                    segmentation_fault(task, fault);
                }
            },
            .Read => {
                segmentation_fault(task, fault);
            },
        }
    } else if (mapping.is_page_mapped(fault.entry)) {
        @import("regions.zig").make_present(fault.faulting_page) catch |e| {
            std.log.err("PAGE FAULT!\n\tcannot map address 0x{x:0>8}:\n\t{s}", .{
                @intFromPtr(fault.faulting_address),
                @errorName(e),
            });
        };
    } else {
        segmentation_fault(task, fault);
    }
}

fn page_fault_handler(frame: InterruptFrame) void {
    const fault = page_fault_from_i386(frame);

    if (fault.present != mapping.is_page_present(fault.entry)) {
        @panic("page fault on a present page! (entry is not invalidated)");
    }

    switch (fault.mode) {
        .Kernel => kernel_page_fault(fault),
        .User => user_page_fault(fault),
    }
}

fn panic(fault: PageFault) void {
    std.log.err(
        \\PAGE FAULT!
        \\  address 0x{x:0>8} is not mapped
        \\  action type: {s}
        \\  mode: {s}
        \\  error: {s}
        \\  current task: {d}
    ,
        .{
            @intFromPtr(fault.faulting_address),
            @tagName(fault.type),
            @tagName(fault.mode),
            if (fault.present) "page-level protection violation" else "page not present",
            @import("../task/scheduler.zig").get_current_task().pid,
        },
    );
}

pub fn set_handler() void {
    const interrupts = @import("../interrupts.zig");
    interrupts.set_intr_gate(.PageFault, interrupts.Handler.create(&page_fault_handler, true));

    if (@import("build_options").optimize == .Debug) {
        const kernel_data = cpu.Selector{ .index = 2, .table = .GDT, .privilege = .Supervisor };
        const kernel_code = cpu.Selector{ .index = 1, .table = .GDT, .privilege = .Supervisor };

        gdt.double_fault_tss.esp = @intFromPtr(&gdt.double_fault_stack) + gdt.double_fault_stack.len;
        gdt.double_fault_tss.ss = kernel_data;
        gdt.double_fault_tss.ds = kernel_data;
        gdt.double_fault_tss.es = kernel_data;
        gdt.double_fault_tss.cs = kernel_code;
        gdt.double_fault_tss.eip = @intFromPtr(&double_fault_entry);
        gdt.double_fault_tss.eflags = @bitCast(cpu.EFlags{ .interrupt_enable = false });

        // Zig debug mode passes a hidden "return address" pointer via ECX through
        // the call chain. The hardware task switch loads ECX from df_tss.ecx (default 0).
        // Point ECX to df_tss.eip so that *ECX is a valid code address, preventing
        // NULL dereferences in logger/format code.
        gdt.double_fault_tss.ecx = @intFromPtr(&gdt.double_fault_tss.eip);
        // NOTE: cr3 is set later by update_double_fault_cr3() after the kernel virtual
        // space is transferred, since transfer() changes CR3.

        const double_fault_selector = cpu.Selector{ .index = 8, .table = .GDT, .privilege = .Supervisor };
        @import("../interrupts.zig").set_task_gate(.DoubleFault, double_fault_selector);
    }
}

/// Must be called after the kernel page directory is active (after transfer()).
pub fn update_double_fault_cr3() void {
    if (@import("build_options").optimize == .Debug) {
        gdt.double_fault_tss.cr3 = cpu.get_cr3();
    }
}

fn double_fault_entry() callconv(.naked) noreturn {
    asm volatile (
    // Clear NT flag (bit 14) so IRET doesn't reverse the task switch
        \\ pushfd
        \\ andl $0xffffbfff, (%%esp)
        \\ popfd
        \\ jmp *%[handler]
        :
        : [handler] "r" (&handle_double_fault),
    );
}

/// Force-unlock all mutexes in the allocation chain used by debug backtraces.
/// Only safe in a terminal panic context (double fault) where we never resume.
fn force_unlock_allocator_mutexes() void {
    const memory = @import("../memory.zig");
    // PageFrameAllocator mutex
    memory.pageFrameAllocator.lock.count = 0;
    // Kernel virtual space mutex
    memory.kernel_virtual_space.lock.count = 0;
    // Global slab cache mutex
    memory.globalCache.lock.count = 0;
    memory.globalCache.cache.lock.count = 0;
}

fn handle_double_fault() noreturn {
    // Clear the busy bit of the TSS descriptor to prevent the CPU from refusing to switch
    gdt.clear_busy_bit(.{ .index = 8 });
    gdt.clear_busy_bit(.{ .index = 7 });

    // Restore TR to the main TSS (index 7).
    // The scheduler sets gdt.tss.esp 0, if TR pointed to double_fault_tss,
    // that field would never be read by the CPU on privilege transitions.
    // Also when TR=df_tss, a subsequent double fault can't switch
    // to df_tss (because it's the current task and busy) → triple fault.
    cpu.load_tss(.{ .index = 7, .table = .GDT, .privilege = .Supervisor });

    // The hardware task switch saved the faulting task's context into the gdt.tss.
    const faulting_esp = gdt.tss.esp;
    const faulting_page: paging.VirtualPagePtr = @ptrFromInt(
        std.mem.alignBackward(usize, faulting_esp, paging.page_size),
    );

    if (!scheduler.is_initialized()) {
        force_unlock_allocator_mutexes();
        @panic("early boot double fault (probably stack overflow)");
    }

    scheduler.enter_critical();

    const faulting_task = scheduler.get_current_task();
    if (faulting_task.is_guard_page(faulting_page)) {
        // terminate the faulting task
        faulting_task.state = .Zombie;
        faulting_task.update_status(.{
            .transition = .Terminated,
            .signaled = true,
            .siginfo = .{
                .si_signo = .{ .valid = .SIGSEGV },
                .si_code = .SI_USER,
                .si_pid = 0,
                .si_addr = @ptrCast(faulting_page),
            },
        });
        std.log.warn("stack overflow: task {d} (guard: 0x{x}), terminating task", .{
            faulting_task.pid,
            @intFromPtr(faulting_page),
        });
        for (@import("../task/task.zig").on_terminate_callback.items) |callback| {
            callback(faulting_task);
        }
        scheduler.schedule();
        unreachable;
    }

    @panic("double fault");
}
