const cie = @import("cie.zig");
const XYZ = cie.XYZ;
const LAB = cie.LAB;
const Profile = cie.Profile;

pub const VGA_RGB = packed struct {
    const Self = @This();

    b: u8,
    g: u8,
    r: u8,

    // From RGB to vga text color ([0-255] -> [0-63])
    pub fn from_rgb(rgb: RGB) Self {
        return rgb.to_vga();
    }

    // From vga text color to RGB ([0-63] -> [0-255])
    pub fn to_rgb(self: Self) RGB {
        return RGB.from_vga(self);
    }

    // From XYZ color space to vga text color
    pub fn from_xyz(color: XYZ) Self {
        return color.to_rgb().to_vga();
    }

    // From vga text color to XYZ color space
    pub fn to_xyz(self: Self) XYZ {
        return RGB.from_vga(self).to_xyz();
    }

    // This method is only here to respect the color interface
    pub fn from_vga(vga: VGA_RGB) VGA_RGB {
        return vga;
    }

    // This method is only here to respect the color interface
    pub fn to_vga(vga: VGA_RGB) VGA_RGB {
        return vga;
    }

    // From web color format to vga text color
    pub fn from_web(web: u24) Self {
        return RGB.from_web(web).to_vga();
    }

    // From vga text color to web color format
    pub fn to_web(self: Self) u24 {
        return RGB.from_vga(self).to_web();
    }

    // Blend two vga colors, the mix is done in the RGB color space
    pub fn blend(self: *Self, other: Self, alpha: f32) *Self {
        var rgb = self.to_rgb();
        self.* = rgb.blend(other.to_rgb(), alpha).to_vga();
        return self;
    }
};

pub const RGB = packed struct {
    const Self = @This();

    b: u8,
    g: u8,
    r: u8,

    // This method is only here to respect the color interface
    pub fn from_rgb(rgb: RGB) RGB {
        return rgb;
    }

    // This method is only here to respect the color interface
    pub fn to_rgb(rgb: RGB) RGB {
        return rgb;
    }

    // From XYZ color space to RGB
    pub fn from_xyz(color: XYZ) RGB {
        return color.to_rgb();
    }

    // From RGB to XYZ color space
    pub fn to_xyz(self: RGB) XYZ {
        return XYZ.from_rgb(self);
    }

    // From vga text color to RGB ([0-63] -> [0-255])
    pub fn from_vga(vga: VGA_RGB) RGB {
        return RGB{
            .r = vga.r << 2,
            .g = vga.g << 2,
            .b = vga.b << 2,
        };
    }

    // From RGB to vga text color ([0-255] -> [0-63])
    pub fn to_vga(self: RGB) VGA_RGB {
        var vga = VGA_RGB{
            .r = (self.r >> 2) + ((self.r >> 1) & 1),
            .g = (self.g >> 2) + ((self.g >> 1) & 1),
            .b = (self.b >> 2) + ((self.b >> 1) & 1),
        };
        if (vga.r == 64) vga.r = 63;
        if (vga.g == 64) vga.g = 63;
        if (vga.b == 64) vga.b = 63;
        return vga;
    }

    // from web color format to RGB
    pub fn from_web(web: u24) RGB {
        return @bitCast(web);
    }

    // from RGB to web color format
    pub fn to_web(self: RGB) u24 {
        return @bitCast(self);
    }

    /// Bilinear interpolation between two vga colors
    pub fn blend(self: *Self, other: RGB, alpha: f32) *Self {
        self.r = (1.0 - alpha) * self.r + alpha * other.r;
        self.g = (1.0 - alpha) * self.g + alpha * other.g;
        self.b = (1.0 - alpha) * self.b + alpha * other.b;
        return self;
    }
};

// test "rgb_to_lab" {
//     const std = @import("std");
//     const testing = std.testing;
//
//     const original_rgb = RGB{ .r = 120, .g = 200, .b = 150 };
//     const lab = original_rgb.to_lab(.B);
//     const converted_rgb = lab.to_rgb();
//
//     const debug = std.debug;
//
//     debug.print("original_rgb: #{x:0>6}\n", .{@as(u24, @bitCast(original_rgb))});
//     debug.print("lab: ({d}, {d}, {d})\n", .{ lab.l, lab.a, lab.b });
//     debug.print("converted: #{x:0>6}\n", .{@as(u24, @bitCast(converted_rgb))});
//
//     debug.print("original: {d} {d} {d}\n", .{ original_rgb.r, original_rgb.g, original_rgb.b });
//     debug.print("converted: {d} {d} {d}\n", .{ converted_rgb.r, converted_rgb.g, converted_rgb.b });
//
//     const tolerance = 1;
//
//     try testing.expect(@abs(original_rgb.r - converted_rgb.r) <= tolerance);
//     try testing.expect(@abs(original_rgb.g - converted_rgb.g) <= tolerance);
//     try testing.expect(@abs(original_rgb.b - converted_rgb.b) <= tolerance);
// }

// test "deltaE2000" {
//     const std = @import("std");
//     const debug = std.debug;
//
//     const _LAB = LAB(.D65);
//     const color_1: _LAB = (RGB{ .r = 120, .g = 200, .b = 150 }).to_lab(.D65);
//     const color_2: _LAB = (RGB{ .r = 100, .g = 180, .b = 140 }).to_lab(.D65);
//
//     const deltaE: f32 = color_1.deltaE2000(color_2);
//     const deltaE_2: f32 = color_2.deltaE2000(color_1);
//
//     debug.print("color_1: ({d}, {d}, {d})\n", .{ color_1.l, color_1.a, color_1.b });
//     debug.print("color_2: ({d}, {d}, {d})\n", .{ color_2.l, color_2.a, color_2.b });
//     debug.print("deltaE: {d:.15}\n", .{deltaE});
//     debug.print("deltaE_2: {d:.15}\n", .{deltaE_2});
// }
