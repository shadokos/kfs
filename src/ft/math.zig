const ft = @import("ft.zig");

pub const pi = 3.14159265358979323846264338327950288419716939937510;

/// pi / 180
pub const rad_per_deg = 0.0174532925199432957692369076848861271344287188854172545609719144;

/// 180 / pi
pub const deg_per_rad = 57.295779513082320876798154814105170332405472466564321549160243861;

pub fn log2(x: anytype) @TypeOf(x) {
    switch (@typeInfo(@TypeOf(x))) {
        .Int, .ComptimeInt => {
            var i: @TypeOf(x) = 0;
            const absolute = abs(@TypeOf(x), x);
            while ((absolute >> @intCast(i)) > 1) : (i += 1) {}
            return i;
        },
        else => unreachable, // todo
    }
}

pub fn IntFittingRange(comptime from: comptime_int, comptime to: comptime_int) type {
    if (from > to) {
        @compileError("invalid range");
    }
    if (from == 0 and to == 0) {
        return u0;
    }

    const absolute_max = if (-from > to) -from else to;
    const bits = @max(log2(absolute_max), 1) + 1; // todo
    const signedness: @import("std").builtin.Signedness = if (from < 0 or to < 0) .signed else .unsigned;
    return ft.meta.Int(signedness, bits + (if (signedness == .signed) 1 else 0));
}

pub fn abs(comptime T: type, n: T) T {
    return switch (@typeInfo(T)) {
        .Int => |int| if (int.signedness == .signed and n < 0) -n else n,
        else => if (n < 0) -n else n,
    };
}

pub fn divCeil(comptime T: type, numerator: T, denominator: T) !T {
    return if (@mod(numerator, denominator) != 0)
        @divFloor(numerator, denominator) + 1
    else
        @divFloor(numerator, denominator);
}

/// Simple implementation of the power function using the zig builtins exp and log
/// This implementaiton is based on the identity x^n = e^(n * log(x))
pub fn pow(comptime T: type, x: T, n: T) T {
    if (x == 0) return if (n > 0) 0 else 1;
    if (x == 1 or n == 0) return 1;
    if (x < 0 and @mod(n, 1) != 0) @panic("Negative base with non-integer exponent");

    return @exp(n * @log(x));
}

/// Computes an approximation of the atan(x) function using polynomial interpolation.
///
/// This implementation reduces the input range of `x` to [-1, 1] using the identity:
///   atan(x) = pi/2 - atan(1/x) for x > 1
///   atan(x) = -pi/2 - atan(1/x) for x < -1
/// This range reduction allows for efficient approximation using a polynomial.
///
/// Within the reduced range, a polynomial interpolation is used using a subset of the Taylor series
/// to compute atan(x). The Taylor series for atan(x) is an alternating series:
///   atan(x) = x - x^3/3 + x^5/5 - x^7/7 + ...
/// We are only using the first few terms of the series to approximate the function.
///
/// Once a first approximation is computed with Taylor Series, the function iteratively refines the result using
/// Newton's method. Newton's method solves the equation tan(theta) - x = 0 by iteratively updating
/// theta:
///   theta_{n+1} = theta_n - (tan(theta_n) - x) / (1 + tan^2(theta_n)).
///   This iterative refinement is done a few times to improve the approximation.
///   The number of iterations and the tolerance can be adjusted to trade off accuracy and performance.
///
pub fn atan(x: f32) f32 {
    const pi_over_2 = pi / 2.0;

    // Reduce the range of x to [-1, 1]
    if (x > 1) return pi_over_2 - atan(1 / x);
    if (x < -1) return -pi_over_2 - atan(1 / x);

    // Polynomial interpolation using a Taylor series.
    // The Taylor series for atan(x) is an alternating series described as:
    // atan(x) = x - x^3/3 + x^5/5 - x^7/7 + ...
    const x2 = x * x;
    var theta = x * (1 - (1.0 / 3.0) * x2 + (1.0 / 5.0) * x2 * x2 - (1.0 / 7.0) * x2 * x2 * x2);

    // Iterative refinement using Newton's method.
    // Newton's method solves tan(theta) - x = 0 by iteratively updating theta:
    // theta_{n+1} = theta_n - (tan(theta_n) - x) / (1 + tan^2(theta_n)).
    const max_iterations = 5;
    const tolerance = 1e-20;

    for (0..max_iterations) |_| {
        const tan_theta = @tan(theta);
        const err = tan_theta - x;
        if (@abs(err) < tolerance) break;
        theta -= err / (1 + tan_theta * tan_theta);
    }

    return theta;
}

///               | atan(y/x),      if x > 0
///               | atan(y/x) + pi, if x < 0 and y >= 0
///               | atan(y/x) - pi, if x < 0 and y < 0
/// atan2(y, x) = | pi / 2,         if x = 0 and y > 0
///               | -pi / 2,        if x = 0 and y < 0
///               | 0,              if x > 0 and y = 0
///               | pi,             if x < 0 and y = 0
///               | undefined,      if x = 0 and y = 0
///
pub fn atan2(y: f32, x: f32) f32 {
    if (x == 0) {
        if (y > 0) return pi / 2.0;
        if (y < 0) return -pi / 2.0;
        return 0; // undefined
    }

    if (x > 0) {
        if (y == 0) return 0;
        return atan(y / x);
    }
    if (y >= 0) return atan(y / x) + pi;
    return atan(y / x) - pi;
}

pub fn degreesToRadians(degrees: f32) f32 {
    return degrees * rad_per_deg;
}

pub fn radiansToDegrees(radians: f32) f32 {
    return radians * deg_per_rad;
}

pub fn clamp(value: anytype, min: anytype, max: anytype) @TypeOf(value) {
    return @min(@max(value, min), max);
}

test "atan" {
    const std = @import("std");

    const range = .{ -1000.0, 1000.0 };
    const tolerance = 1e-6;
    const step = 0.5;

    var x: f32 = range[0];
    while (x < range[1]) : (x += step) {
        const expected = std.math.atan(x);
        const actual = atan(x);
        const diff = @abs(expected - actual);
        if (!(diff <= tolerance)) {
            std.debug.print("x: {}, expected: {}, actual: {}, diff: {}\n", .{ x, expected, actual, diff });
            try std.testing.expect(diff <= tolerance);
        }
    }
}

test "atan2" {
    const std = @import("std");

    const x_range = .{ -1000.0, 1000.0 };
    const y_range = .{ 1000.0, -1000.0 };
    const tolerance = 1e-6;
    const step = 0.5;

    var x: f32 = x_range[0];
    while (x < x_range[1]) : (x += step) {
        var y: f32 = y_range[0];
        while (y < y_range[1]) : (y -= step) {
            const expected = std.math.atan2(y, x);
            const actual = atan2(y, x);
            const diff = @abs(expected - actual);
            if (!(diff <= tolerance)) {
                std.debug.print(
                    "x: {}, y: {}, expected: {}, actual: {}, diff: {}\n",
                    .{ x, y, expected, actual, diff },
                );
                try std.testing.expect(diff <= tolerance);
            }
        }
    }
}

test "pow" {
    const std = @import("std");

    const x_range = .{ -1000.0, 1000.0 };
    const n_range = .{ 1000.0, -1000.0 };

    const tolerance = 1e-20;
    const step = 0.5;

    var x: f32 = x_range[0];
    while (x < x_range[1]) : (x += step) {
        var n: f32 = n_range[0];
        while (n < n_range[1]) : (n -= step) {
            const expected = std.math.pow(f32, x, n);
            const actual = pow(f32, x, n);
            const diff = @abs(expected - actual);
            if (!(diff <= tolerance)) {
                std.debug.print(
                    "x: {}, n: {}, expected: {}, actual: {}, diff: {}\n",
                    .{ x, n, expected, actual, diff },
                );
                try std.testing.expect(diff <= tolerance);
            }
        }
    }
}
