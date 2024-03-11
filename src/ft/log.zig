pub const Level = enum {
	err,
	warn,
	info,
	debug,

	pub fn asText(comptime self: Level) []const u8 {
		return switch (self) {
			.err => "error",
			.warn => "warning",
			.info => "info",
			.debug => "debug"
		};
	}
};

pub const default_level = Level.debug; // TODO: Adapt to build mode

pub const level = @import("ft.zig").options.log_level;

pub const default_log_scope = .default;

pub fn defaultLog(comptime message_level: Level, comptime scope: anytype, comptime format: []const u8, args: anytype) void {
	_ = scope; _ = level; _ = message_level; _ = format; _ = args;
}

// fn defaultLogEnabled(comptime message_level: Level) bool
// fn logEnabled(comptime message_level: Level, comptime scope: anytype) bool

pub fn logEnabled(comptime message_level: Level, comptime scope: anytype) bool {
	_ = scope; // TODO: Implement scope based log level, for now we just use the global level
	return (@intFromEnum(message_level) <= @intFromEnum(level));
}

pub fn log(comptime message_level: Level, comptime scope: anytype, comptime format: []const u8, args: anytype) void {
	if (logEnabled(message_level, scope)) @import("ft.zig").options.logFn(message_level, scope, format, args);
}

pub fn scoped(comptime scope: @Type(.EnumLiteral)) type {
	return struct {
		pub fn err(comptime format: []const u8, args: anytype) void {
			@setCold(true);
			log(.err, scope, format, args);
		}

		pub fn warn(comptime format: []const u8, args: anytype) void {
			log(.warn, scope, format, args);
		}

		pub fn info(comptime format: []const u8, args: anytype) void {
			log(.info, scope, format, args);
		}

		pub fn debug(comptime format: []const u8, args: anytype) void {
			log(.debug, scope, format, args);
		}
	};
}
