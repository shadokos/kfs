
pub const mem = @import("mem.zig");

pub const fmt = @import("fmt.zig");

pub const ascii = @import("ascii.zig");

pub const io = @import("io.zig");

pub const meta = @import("meta.zig");

pub const math = @import("math.zig");

pub const debug = @import("debug.zig");

pub const Random = @import("Random.zig");

pub const log = @import("log.zig");

const root = @import("root");
pub const options: Options = if (@hasDecl(root, "ft_options")) root.ft_options else .{};

pub const Options = struct {
	log_level: log.Level = log.default_level,
	logFn: @TypeOf(log.defaultLog) = log.defaultLog,
};