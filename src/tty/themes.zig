const vga = @import("../drivers/vga/text.zig");
const themes = @import("themes/index.zig");
const ft = @import("ft");
const config = @import("config");
const colors = @import("colors");

// const vga_diff = @import("colors").vga_diff;

pub const Theme = struct {
    palette: vga.Palette,
    background: vga.Color,
    foreground: vga.Color,
    background_idx: u8 = 0,
    foreground_idx: u8 = 7,
};

/// try to convert a gogh theme to a vga theme
pub fn convert(theme: Theme) Theme {
    var ret: Theme = theme;
    ft.mem.swap(vga.Color, &ret.palette[1], &ret.palette[4]);
    ft.mem.swap(vga.Color, &ret.palette[3], &ret.palette[6]);
    ft.mem.swap(vga.Color, &ret.palette[8 + 1], &ret.palette[8 + 4]);
    ft.mem.swap(vga.Color, &ret.palette[8 + 3], &ret.palette[8 + 6]);

    // Get the color difference function
    const delta_e = switch (config.theme.delta_e) {
        .CIEDE2000 => colors.LAB(config.theme.profile).deltaE2000,
        .CIE76 => colors.LAB(config.theme.profile).deltaE,
    };

    for (ret.palette[0..16], 0..) |c, i| {
        if (delta_e(theme.foreground, c) < delta_e(theme.foreground, theme.palette[ret.foreground_idx])) {
            ret.foreground_idx = i;
        }
        if (delta_e(theme.background, c) < delta_e(theme.background, theme.palette[ret.background_idx])) {
            ret.background_idx = i;
        }
    }

    // if foreground and background are still the same,
    // then we iterate over the palette to find the next best color matching the default background
    var min_diff: f32 = 1e9;
    if (ret.background_idx % 8 == ret.foreground_idx % 8) {
        for (ret.palette[0..16], 0..) |c, i| {
            if (i % 8 == ret.foreground_idx % 8) continue;
            const diff = theme.background.deltaE2000(c);
            if (diff < min_diff) {
                ret.background_idx = i;
                min_diff = diff;
            }
        }
    }

    _ = ret.palette[ret.foreground_idx].blend(
        theme.foreground,
        config.theme.foreground_blend,
    );
    _ = ret.palette[ret.background_idx].blend(
        theme.background,
        config.theme.background_blend,
    );
    return ret;
}

/// return a theme by its name
pub fn get_theme(name: []const u8) ?Theme {
    inline for (@typeInfo(themes).@"struct".decls) |decl| {
        if (ft.mem.eql(u8, decl.name, name)) {
            return @field(themes, decl.name).theme;
        }
    }
    return null;
}

/// return a list of the available themes
fn get_theme_list() [@typeInfo(themes).@"struct".decls.len][]const u8 {
    comptime {
        var ret: [@typeInfo(themes).@"struct".decls.len][]const u8 = undefined;
        for (@typeInfo(themes).@"struct".decls, 0..) |decl, i| {
            ret[i] = decl.name;
        }
        return ret;
    }
}

/// list of all the existing themes
pub const theme_list = get_theme_list();

/// default theme
pub const default: ?Theme = if (theme_list.len > 0) get_theme(theme_list[0]) else null;
