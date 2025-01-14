const ft = @import("ft");
const token = @import("token.zig");
const colors = @import("colors");
const allocator = @import("../memory.zig").smallAlloc.allocator();
const task = @import("../task/task.zig");
const task_set = @import("../task/task_set.zig");

pub const CmdError = error{ CommandNotFound, InvalidNumberOfArguments, InvalidParameter, OtherError };
pub const Config = struct {
    colors: bool = true,
};

const max_line_size: u16 = 1024;

pub fn Shell(comptime _builtins: anytype) type {
    return struct {
        const builtins = _builtins;
        const Self = @This();

        const Hook: type = ?*const fn (*Self) void;

        const Hooks: type = struct {
            on_init: Hook = null,
            on_error: Hook = defaultErrorHook,
            pre_prompt: Hook = null,
            pre_cmd: Hook = null,
            post_cmd: Hook = null,
        };

        const ExecutionContext = struct {
            args: [][]u8,
            detach: bool = false,
            err: ?anyerror,
        };
        const Job = struct {
            pid: task.TaskDescriptor.Pid,
            command_line: []u8,
        };

        config: Config = Config{},
        execution_context: ExecutionContext = ExecutionContext{
            .args = undefined,
            .err = null,
        },
        reader: ft.io.AnyReader = undefined,
        writer: ft.io.AnyWriter = undefined,
        hooks: Hooks = Hooks{},
        jobs: ft.ArrayList(Job) = undefined,

        pub fn init(
            reader: ft.io.AnyReader,
            writer: ft.io.AnyWriter,
            config: Config,
            hooks: struct {
                on_init: ?*const anyopaque = null,
                on_error: ?*const anyopaque = null,
                pre_prompt: ?*const anyopaque = null,
                pre_cmd: ?*const anyopaque = null,
                post_cmd: ?*const anyopaque = null,
            },
        ) Self {
            var ret = Self{
                .jobs = ft.ArrayList(Job).init(allocator),
                .reader = reader,
                .writer = writer,
                .config = config,
            };
            if (hooks.on_init) |h| ret.hooks.on_init = @alignCast(@ptrCast(h));
            if (hooks.on_error) |h| ret.hooks.on_error = @alignCast(@ptrCast(h));
            if (hooks.pre_prompt) |h| ret.hooks.pre_prompt = @alignCast(@ptrCast(h));
            if (hooks.pre_cmd) |h| ret.hooks.pre_cmd = @alignCast(@ptrCast(h));
            if (hooks.post_cmd) |h| ret.hooks.post_cmd = @alignCast(@ptrCast(h));
            if (ret.hooks.on_init) |hook| hook(@constCast(&ret));
            return ret;
        }

        fn cmd_arguments(function: anytype) type {
            return struct {
                shell: *Self,
                args: [][]u8,

                fn start_cmd(data: anytype) u8 {
                    const self: *cmd_arguments(function) = data;
                    const ret: u8 = if (function(self.shell, self.args)) |_| 0 else |e| @truncate(
                        @intFromError(e),
                    ); //todo
                    allocator.destroy(self);
                    return ret;
                }
            };
        }

        fn exec_detached(self: *Self, comptime function: anytype, args: [][]u8) ?task.TaskDescriptor.Pid {
            const CmdStruct = cmd_arguments(function);
            const arg_struct: *CmdStruct = allocator.create(CmdStruct) catch {
                self.print_error("Out of space", .{});
                return null;
            };
            arg_struct.* = .{
                .shell = self,
                .args = args,
            };
            const descriptor = task_set.create_task() catch @panic("c'est  la  panique 5"); // todo
            descriptor.spawn(&CmdStruct.start_cmd, arg_struct) catch @panic("c'est  la  panique 5");
            return descriptor.pid;
        }

        fn exec_cmd(self: *Self, args: [][]u8, detach: bool) CmdError!?task.TaskDescriptor.Pid {
            // Search for a builtin command by iterating over those defined in shell/builtins.zig
            inline for (@typeInfo(builtins).@"struct".decls) |decl| {
                if (ft.mem.eql(u8, decl.name, args[0])) {
                    if (detach) {
                        return self.exec_detached(@field(builtins, decl.name), args);
                    } else {
                        try @field(builtins, decl.name)(self, args);
                        return null;
                    }
                }
            }
            return CmdError.CommandNotFound;
        }

        fn wait_childs(self: *Self) void {
            const wait = @import("../task/wait.zig");
            var status: wait.Status = undefined;
            var i: u32 = 0;
            while (i < self.jobs.slice.len) {
                const job = self.jobs.slice[i];
                if (wait.wait(job.pid, .SELF, &status, .{ .WNOHANG = true }) catch @panic("todo")) |_| {
                    self.print("[{}] done {s}\n", .{ job.pid, job.command_line });
                    allocator.destroy(job.command_line);
                    _ = self.jobs.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        pub fn process_line(self: *Self) void {
            self.wait_childs();

            self.execution_context.args = &.{};
            if (self.hooks.pre_prompt) |hook| hook(self);

            // Read a line from the reader
            const slice = self.reader.readUntilDelimiterAlloc(allocator, '\n', max_line_size) catch |e| {
                if (e == error.EndOfStream) return;
                self.execution_context.err = e;
                if (self.hooks.on_error) |hook| hook(self);
                return;
            };

            // Tokenize the line
            self.execution_context.args = token.tokenize(slice) catch |e| {
                self.execution_context.err = e;
                if (self.hooks.on_error) |hook| hook(self);
                return;
            };
            if (self.execution_context.args.len > 0 and ft.mem.eql(u8, self.execution_context.args[0], "&")) {
                self.execution_context.detach = true;
                self.execution_context.args = self.execution_context.args[1..];
            } else {
                self.execution_context.detach = false;
            }
            if (self.execution_context.args.len == 0) return;

            if (self.hooks.pre_cmd) |hook| hook(self);

            self.execution_context.err = null;
            if (self.exec_cmd(self.execution_context.args, self.execution_context.detach) catch |e| {
                self.execution_context.err = e;
                if (self.hooks.on_error) |hook| hook(self);
                allocator.free(slice);
                return;
            }) |pid| {
                self.jobs.append(.{ .pid = pid, .command_line = slice }) catch @panic("todo");
                self.print("[{}]\n", .{pid});
            } else {
                allocator.free(slice);
            }
            if (self.hooks.post_cmd) |hook| hook(self);
        }

        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.writer.print(fmt, args) catch {};
        }

        pub fn print_error(self: *Self, comptime fmt: []const u8, args: anytype) void {
            const red = if (self.config.colors) colors.red else "";
            const reset = if (self.config.colors) colors.reset else "";
            self.writer.print("{s}Error{s}: " ++ fmt ++ "\n", .{ red, reset } ++ args) catch {};
        }

        pub fn strerror(_: *Self, err: anyerror) []const u8 {
            switch (err) {
                error.StreamTooLong => return "Stream too long",
                error.CommandNotFound => return "Command not found",
                error.InvalidNumberOfArguments => return "Invalid number of arguments",
                error.InvalidParameter => return "Invalid parameter",
                error.InvalidQuote => return "Invalid quote",
                error.MaxTokensReached => return "Max tokens reached",
                else => return "Unknown error",
            }
        }

        pub fn defaultErrorHook(shell: *Self) void {
            const err = shell.execution_context.err orelse return;
            const args = shell.execution_context.args;

            switch (err) {
                error.OtherError => {}, // specific errors are handled by the command itself
                error.StreamTooLong => {
                    shell.print_error("Line is too long", .{});
                    _ = shell.reader.skipUntilDelimiterOrEof('\n') catch {};
                },
                error.CommandNotFound => shell.print_error("{s}: {s}", .{ args[0], shell.strerror(err) }),
                error.MaxTokensReached => shell.print_error(
                    "too many tokens (max: {d})",
                    .{token.max_tokens},
                ),
                error.InvalidNumberOfArguments,
                error.InvalidParameter,
                error.InvalidQuote,
                => shell.print_error("{s}", .{shell.strerror(err)}),
                else => shell.print_error("Unknown error: {s}", .{@errorName(err)}),
            }
        }
    };
}
