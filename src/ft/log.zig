pub const Level = enum {
	err,
	warn,
	info,
	debug,

	pub fn asText(comptime self: Level) []const u8 {
		return switch (self) {
			.err => "ERROR",
			.warn => "WARNING",
			.info => "INFO",
			.debug => "DEBUG"
		};
	}
};

// the default log scope (used in ft.Options as log_level default value)
pub const default_level = Level.debug; // TODO: Adapt to build mode

// the default log scope (a literal enum used for default scope)
pub const default_log_scope = .default;

// the default scope
pub const default = scoped(default_log_scope);

pub fn defaultLog(
	comptime message_level: Level,
	comptime scope: anytype,
	comptime format: []const u8,
	args: anytype
) void {
	// TODO: Maybe implement a default log function using tty.printk??
	_ = scope; _ = level; _ = message_level; _ = format; _ = args;
}

// the global log level is set in the ft_options struct defined in the root module
// if the log level is not set in the options, the default_level is used (see src/ft/ft.zig)
pub const level = @import("ft.zig").options.log_level;

// fn defaultLogEnabled(comptime message_level: Level) bool

pub fn logEnabled(comptime message_level: Level, comptime scope: anytype) bool {
	_ = scope; // TODO: Implement scope based log level, for now we just use the global level
	return (@intFromEnum(message_level) <= @intFromEnum(level));
}

pub fn log(
	comptime message_level: Level,
	comptime scope: anytype,
	comptime format: []const u8,
	args: anytype
) void {
	if (logEnabled(message_level, scope))
		@import("ft.zig").options.logFn(message_level, scope, format, args);
}

pub fn err(comptime format: []const u8, args: anytype) void {
	@setCold(true);
	log(.err, default_log_scope, format, args);
}

pub fn warn(comptime format: []const u8, args: anytype) void {
	log(.warn, default_log_scope, format, args);
}

pub fn info(comptime format: []const u8, args: anytype) void {
	log(.info, default_log_scope, format, args);
}

pub fn debug(comptime format: []const u8, args: anytype) void {
	log(.debug, default_log_scope, format, args);
}

pub fn scoped(comptime scope: anytype) type {
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