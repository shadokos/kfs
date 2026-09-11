const std = @import("std");

pub const major_t = u8;
pub const minor_t = u8;

pub const dev_t = packed struct {
    minor: minor_t,
    major: major_t,

    pub fn toInt(self: dev_t) udev_t {
        return @bitCast(self);
    }

    pub fn fromInt(value: udev_t) dev_t {
        return @bitCast(value);
    }
};

// Unsigned version of dev_t
pub const udev_t = std.meta.Int(.unsigned, @bitSizeOf(dev_t));
