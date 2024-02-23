const vga = @import("../drivers/vga/text.zig");
const themes = @import("themes/index.zig");
const ft = @import("../ft/ft.zig");

pub const Theme = struct {
	palette : vga.Palette,
	background : vga.Color,
	foreground : vga.Color,
	background_idx : u8 = 0,
	foreground_idx : u8 = 7,
};

/// compute the difference between two colors
fn color_diff(l : vga.Color, r : vga.Color) usize {
	return	(@as(i32, @intCast(l.r)) - @as(i32, @intCast(r.r))) * (@as(i32, @intCast(l.r)) - @as(i32, @intCast(r.r))) +
			(@as(i32, @intCast(l.g)) - @as(i32, @intCast(r.g))) * (@as(i32, @intCast(l.g)) - @as(i32, @intCast(r.g))) +
			(@as(i32, @intCast(l.b)) - @as(i32, @intCast(r.b))) * (@as(i32, @intCast(l.b)) - @as(i32, @intCast(r.b)));
}

/// try to convert a gogh theme to a vga theme
pub fn convert(theme : Theme) Theme {
	var ret : Theme = theme;
	ft.mem.swap(vga.Color, &ret.palette[1], &ret.palette[4]);
	ft.mem.swap(vga.Color, &ret.palette[3], &ret.palette[6]);
	ft.mem.swap(vga.Color, &ret.palette[8 + 1], &ret.palette[8 + 4]);
	ft.mem.swap(vga.Color, &ret.palette[8 + 3], &ret.palette[8 + 6]);
	for (ret.palette[0..16], 0..) |c, i| {
		if (color_diff(theme.foreground, c) < color_diff(theme.foreground, theme.palette[ret.foreground_idx])) {
			ret.foreground_idx = i;
		}
		if (color_diff(ret.background, c) < color_diff(ret.background, theme.palette[ret.background_idx])) {
			ret.background_idx = i;
		}
	}
	return ret;
}

/// return a theme by its name
pub fn get_theme(name : []const u8) ?Theme {
	inline for (@typeInfo(themes).Struct.decls) |decl| {
		if (ft.mem.eql(u8, decl.name, name)) {
			return @field(themes, decl.name).theme;
		}
	}
	return null;
}

/// return a list of the available themes
fn get_theme_list() [@typeInfo(themes).Struct.decls.len][]const u8 {
	comptime {
		var ret : [@typeInfo(themes).Struct.decls.len][]const u8 = undefined;
		inline for (@typeInfo(themes).Struct.decls, 0..) |decl, i| {
			ret[i] = decl.name;
		}
		return ret;
	}
}

/// list of all the existing themes
pub const theme_list = get_theme_list();

/// default theme
pub const default : ?Theme = get_theme("Gogh") orelse (if (theme_list.len > 0) get_theme(theme_list[0]) else null);