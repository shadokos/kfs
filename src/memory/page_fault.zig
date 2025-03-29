const ft = @import("ft");
const paging = @import("paging.zig");
const regions = @import("regions.zig");
const Region = regions.Region;
const cpu = @import("../cpu.zig");
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
    const page: usize = ft.mem.alignBackward(usize, cr2, paging.page_size);
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
            ft.log.err("PAGE FAULT!\n\tcannot map address 0x{x:0>8}:\n\t{s}", .{
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
            ft.log.err("PAGE FAULT!\n\tcannot map address 0x{x:0>8}:\n\t{s}", .{
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
    ft.log.err(
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
}
