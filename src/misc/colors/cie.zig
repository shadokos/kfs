const std = @import("std");
const config = @import("config");
const RGB = @import("rgb.zig").RGB;
const VGA_RGB = @import("rgb.zig").VGA_RGB;

// CIE-LAB delta E 2000 weights
pub const Kde2000 = packed struct {
    L: f32 = 1.0,
    C: f32 = 1.0,
    H: f32 = 1.0,
};

pub const Profile = struct {
    const Self = @This();

    pub const Items = enum { A, B, C, D50, D55, D65, D75, E, F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12, None };

    x: f32,
    y: f32,
    z: f32,

    pub fn get_value(ref: Items) Self {
        return switch (ref) {
            .A => .{ .x = 109.850, .y = 100.000, .z = 35.585 }, // Incandescent/tungsten
            .B => .{ .x = 99.0927, .y = 100.000, .z = 85.313 }, // Old direct sunlight at noon
            .C => .{ .x = 98.074, .y = 100.000, .z = 118.232 }, // Old daylight
            .D50 => .{ .x = 96.422, .y = 100.000, .z = 82.521 }, // ICC profile PCS
            .D55 => .{ .x = 95.682, .y = 100.000, .z = 92.149 }, // Mid-morning daylight
            .D65 => .{ .x = 95.047, .y = 100.000, .z = 108.883 }, // Daylight, sRGB, Adobe-RGB
            .D75 => .{ .x = 94.972, .y = 100.000, .z = 122.638 }, // North sky daylight
            .E => .{ .x = 100.000, .y = 100.000, .z = 100.000 }, // Equal energy
            .F1 => .{ .x = 92.834, .y = 100.000, .z = 103.665 }, // Daylight Fluorescent
            .F2 => .{ .x = 99.187, .y = 100.000, .z = 67.395 }, // Cool fluorescent
            .F3 => .{ .x = 103.754, .y = 100.000, .z = 49.861 }, // White Fluorescent
            .F4 => .{ .x = 109.147, .y = 100.000, .z = 38.813 }, // Warm White Fluorescent
            .F5 => .{ .x = 90.872, .y = 100.000, .z = 98.723 }, // Daylight Fluorescent
            .F6 => .{ .x = 97.309, .y = 100.000, .z = 60.191 }, // Lite White Fluorescent
            .F7 => .{ .x = 95.044, .y = 100.000, .z = 108.755 }, // Daylight fluorescent, D65 simulator
            .F8 => .{ .x = 96.413, .y = 100.000, .z = 82.333 }, // Sylvania F40, D50 simulator
            .F9 => .{ .x = 100.365, .y = 100.000, .z = 67.868 }, // Cool White Fluorescent
            .F10 => .{ .x = 96.174, .y = 100.000, .z = 81.712 }, // Ultralume 50, Philips TL85
            .F11 => .{ .x = 100.966, .y = 100.000, .z = 64.370 }, // Ultralume 40, Philips TL84
            .F12 => .{ .x = 108.046, .y = 100.000, .z = 39.228 }, // Ultralume 30, Philips TL83
            .None => .{ .x = 100.0, .y = 100.0, .z = 100.0 },
        };
    }
};

// CIE-LAB color space
pub const XYZ = packed struct {
    const Self = @This();

    x: f32,
    y: f32,
    z: f32,

    pub fn from_rgb(color: RGB) Self {
        var r = @as(f32, @floatFromInt(color.r)) / 255.0;
        var g = @as(f32, @floatFromInt(color.g)) / 255.0;
        var b = @as(f32, @floatFromInt(color.b)) / 255.0;

        @setEvalBranchQuota(10000);
        r = if (r > 0.04045) std.math.pow(f32, (r + 0.055) / 1.055, 2.4) else r / 12.92;
        g = if (g > 0.04045) std.math.pow(f32, (g + 0.055) / 1.055, 2.4) else g / 12.92;
        b = if (b > 0.04045) std.math.pow(f32, (b + 0.055) / 1.055, 2.4) else b / 12.92;

        r *= 100.0;
        g *= 100.0;
        b *= 100.0;

        return .{
            .x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375,
            .y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750,
            .z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041,
        };
    }

    pub fn to_rgb(self: Self) RGB {
        const x = self.x / 100.0;
        const y = self.y / 100.0;
        const z = self.z / 100.0;

        var r = x * 3.2406 + y * -1.5372 + z * -0.4986;
        var g = x * -0.9689 + y * 1.8758 + z * 0.0415;
        var b = x * 0.0557 + y * -0.2040 + z * 1.0570;

        r = if (r > 0.0031308) 1.055 * std.math.pow(f32, r, 1.0 / 2.4) - 0.055 else 12.92 * r;
        g = if (g > 0.0031308) 1.055 * std.math.pow(f32, g, 1.0 / 2.4) - 0.055 else 12.92 * g;
        b = if (b > 0.0031308) 1.055 * std.math.pow(f32, b, 1.0 / 2.4) - 0.055 else 12.92 * b;

        return RGB{
            .r = @intFromFloat(std.math.clamp(r * 255.0, 0.0, 255.0)),
            .g = @intFromFloat(std.math.clamp(g * 255.0, 0.0, 255.0)),
            .b = @intFromFloat(std.math.clamp(b * 255.0, 0.0, 255.0)),
        };
    }

    // This method is only here to respect the color interface
    pub fn from_xyz(color: XYZ) Self {
        return color;
    }

    // This method is only here to respect the color interface
    pub fn to_xyz(self: Self) XYZ {
        return self;
    }

    pub fn from_vga(color: VGA_RGB) Self {
        return RGB.from_vga(color).to_xyz();
    }

    pub fn to_vga(self: Self) VGA_RGB {
        return self.to_rgb().to_vga();
    }

    pub fn from_web(color: u24) Self {
        return RGB.from_web(color).to_xyz();
    }

    pub fn to_web(self: Self) u24 {
        return self.to_rgb().to_web();
    }

    pub fn blend(self: *Self, other: Self, alpha: f32) *Self {
        self.* = .{
            .x = (1.0 - alpha) * self.x + alpha * other.x,
            .y = (1.0 - alpha) * self.y + alpha * other.y,
            .z = (1.0 - alpha) * self.z + alpha * other.z,
        };
        return self;
    }
};

pub fn LAB(comptime ref: Profile.Items) type {
    const ref_values = Profile.get_value(ref);

    return packed struct {
        const Self = @This();

        l: f32,
        a: f32,
        b: f32,

        pub fn from_rgb(color: RGB) Self {
            return Self.from_xyz(XYZ.from_rgb(color));
        }

        pub fn to_rgb(self: Self) RGB {
            return self.to_xyz().to_rgb();
        }

        pub fn from_xyz(color: XYZ) Self {
            var x = color.x / ref_values.x;
            var y = color.y / ref_values.y;
            var z = color.z / ref_values.z;

            x = if (x > 0.008856) std.math.pow(f32, x, 1.0 / 3.0) else (7.787 * x) + (16.0 / 116.0);
            y = if (y > 0.008856) std.math.pow(f32, y, 1.0 / 3.0) else (7.787 * y) + (16.0 / 116.0);
            z = if (z > 0.008856) std.math.pow(f32, z, 1.0 / 3.0) else (7.787 * z) + (16.0 / 116.0);

            return .{
                .l = (116.0 * y) - 16.0,
                .a = 500.0 * (x - y),
                .b = 200.0 * (y - z),
            };
        }

        pub fn to_xyz(self: Self) XYZ {
            var y = (self.l + 16.0) / 116.0;
            var x = self.a / 500.0 + y;
            var z = y - self.b / 200.0;

            y = if (std.math.pow(f32, y, 3.0) > 0.008856) std.math.pow(f32, y, 3.0) else (y - 16.0 / 116.0) / 7.787;
            x = if (std.math.pow(f32, x, 3.0) > 0.008856) std.math.pow(f32, x, 3.0) else (x - 16.0 / 116.0) / 7.787;
            z = if (std.math.pow(f32, z, 3.0) > 0.008856) std.math.pow(f32, z, 3.0) else (z - 16.0 / 116.0) / 7.787;

            return .{
                .x = x * ref_values.x,
                .y = y * ref_values.y,
                .z = z * ref_values.z,
            };
        }

        pub fn from_vga(color: VGA_RGB) Self {
            return Self.from_xyz(XYZ.from_vga(color));
        }

        pub fn to_vga(self: Self) VGA_RGB {
            return self.to_xyz().to_vga();
        }

        pub fn from_web(color: u24) Self {
            return Self.from_rgb(RGB.from_web(color));
        }

        pub fn to_web(self: Self) u24 {
            return self.to_rgb().to_web();
        }

        pub fn blend(self: *Self, other: Self, alpha: f32) *Self {
            self.* = .{
                .l = (1.0 - alpha) * self.l + alpha * other.l,
                .a = (1.0 - alpha) * self.a + alpha * other.a,
                .b = (1.0 - alpha) * self.b + alpha * other.b,
            };
            return self;
        }

        // CIE76 color difference : https://easyrgb.com/en/math.php (Delta E* CIE)
        pub fn deltaE(self: Self, other: Self) f32 {
            const dl = other.l - self.l;
            const da = other.a - self.a;
            const db = other.b - self.b;

            return @sqrt(dl * dl + da * da + db * db);
        }

        // Lab to Hue, used in CIEDE2000
        fn cieLab2Hue(var_a: f32, var_b: f32) f32 {
            if (var_a >= 0 and var_b == 0) return 0;
            if (var_a < 0 and var_b == 0) return 180;
            if (var_a == 0 and var_b > 0) return 90;
            if (var_a == 0 and var_b < 0) return 270;

            const angle = std.math.radiansToDegrees(std.math.atan2(var_b, var_a));
            if (var_a > 0 and var_b > 0) return angle;
            if (var_a < 0) return angle + 180;
            if (var_a > 0 and var_b < 0) return angle + 360;
            return angle;
        }

        // CIEDE2000 color difference : https://easyrgb.com/en/math.php (Delta E_{2000})
        pub fn deltaE2000(self: Self, other: Self) f32 {
            // calculate C1 and C2 (chroma values)
            const C1 = @sqrt(self.a * self.a + self.b * self.b);
            const C2 = @sqrt(other.a * other.a + other.b * other.b);

            // calculate average chroma
            const Cb = (C1 + C2) / 2.0;

            // calculate G (chroma weight)
            const pow7 = std.math.pow(f32, Cb, 7.0);
            const G = 0.5 * (1.0 - @sqrt(pow7 / (pow7 + std.math.pow(f32, 25.0, 7.0))));

            // calculate modified A values
            const a1p = (1.0 + G) * self.a;
            const a2p = (1.0 + G) * other.a;

            // calculate C' values
            const C1p = @sqrt(a1p * a1p + self.b * self.b);
            const C2p = @sqrt(a2p * a2p + other.b * other.b);

            // calculate h' values
            const h1p = cieLab2Hue(a1p, self.b);
            const h2p = cieLab2Hue(a2p, other.b);

            // calculate ΔL', ΔC'
            const dL = other.l - self.l;
            const dC = C2p - C1p;

            // calculate ΔH'
            var dH: f32 = 0.0;
            if (C1p * C2p != 0) {
                const dhp = h2p - h1p;
                if (@abs(dhp) <= 180.0) {
                    dH = dhp;
                } else if (dhp > 180.0) {
                    dH = dhp - 360.0;
                } else {
                    dH = dhp + 360.0;
                }
                dH = 2.0 * @sqrt(C1p * C2p) * @sin(std.math.degreesToRadians(dH / 2.0));
            }

            // calculate average L', C'
            const Lp = (self.l + other.l) / 2.0;
            const Cp = (C1p + C2p) / 2.0;

            // calculate H'
            var Hp: f32 = h1p + h2p;
            if (C1p * C2p != 0) {
                if (@abs(h1p - h2p) > 180.0) {
                    if (h1p + h2p < 360.0) {
                        Hp += 360.0;
                    } else {
                        Hp -= 360.0;
                    }
                }
                Hp /= 2.0;
            }

            @setEvalBranchQuota(2000);

            // calculate T
            const T = 1.0 - 0.17 * @cos(std.math.degreesToRadians(Hp - 30.0)) +
                0.24 * @cos(std.math.degreesToRadians(2.0 * Hp)) +
                0.32 * @cos(std.math.degreesToRadians(3.0 * Hp + 6.0)) -
                0.20 * @cos(std.math.degreesToRadians(4.0 * Hp - 63.0));

            // calculate ΔΘ
            const dTheta = 30.0 * @exp(-((Hp - 275.0) / 25.0) * ((Hp - 275.0) / 25.0));

            // The following operations are actually quite expensive
            @setEvalBranchQuota(40000);

            // calculate RC
            const pow7_Cp = std.math.pow(f32, Cp, 7.0);
            const RC = 2.0 * @sqrt(pow7_Cp / (pow7_Cp + std.math.pow(f32, 25.0, 7.0)));

            // calculate SL, SC, SH
            const SL = 1.0 + ((0.015 * (Lp - 50.0) * (Lp - 50.0)) /
                @sqrt(20.0 + (Lp - 50.0) * (Lp - 50.0)));
            const SC = 1.0 + 0.045 * Cp;
            const SH = 1.0 + 0.015 * Cp * T;

            // calculate RT
            const RT = -@sin(std.math.degreesToRadians(2.0 * dTheta)) * RC;

            const k = config.theme.k_de;

            // calculate final ΔE
            const dL_term = dL / (k.L * SL);
            const dC_term = dC / (k.C * SC);
            const dH_term = dH / (k.H * SH);

            return @sqrt(dL_term * dL_term +
                dC_term * dC_term +
                dH_term * dH_term +
                RT * dC_term * dH_term);
        }
    };
}
