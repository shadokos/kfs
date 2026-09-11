pub const bold = "\x1b[1m";
pub const dim = "\x1b[2m";
pub const invert = "\x1b[7m";
pub const reset = "\x1b[0m";

pub const black = "\x1b[30m";
pub const red = "\x1b[31m";
pub const green = "\x1b[32m";
pub const yellow = "\x1b[33m";
pub const blue = "\x1b[34m";
pub const magenta = "\x1b[35m";
pub const cyan = "\x1b[36m";
pub const white = "\x1b[37m";

pub const bg_black = "\x1b[40m";
pub const bg_red = "\x1b[41m";
pub const bg_green = "\x1b[42m";
pub const bg_yellow = "\x1b[43m";
pub const bg_blue = "\x1b[44m";
pub const bg_magenta = "\x1b[45m";
pub const bg_cyan = "\x1b[46m";
pub const bg_white = "\x1b[47m";

pub const rgb = @import("colors/rgb.zig");
pub const cie = @import("colors/cie.zig");

pub const RGB = rgb.RGB;
pub const VGA_RGB = rgb.VGA_RGB;
pub const XYZ = cie.XYZ;
pub const LAB = cie.LAB;

// CIE Color profile type
pub const Profile = cie.Profile;

// CIE-LAB delta E 2000 weights type
pub const Kde2000 = cie.Kde2000;
