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

pub const black_bold = bold ++ black;
pub const red_bold = bold ++ red;
pub const green_bold = bold ++ green;
pub const yellow_bold = bold ++ yellow;
pub const blue_bold = bold ++ blue;
pub const magenta_bold = bold ++ magenta;
pub const cyan_bold = bold ++ cyan;
pub const white_bold = bold ++ white;

pub const black_dim = dim ++ black;
pub const red_dim = dim ++ red;
pub const green_dim = dim ++ green;
pub const yellow_dim = dim ++ yellow;
pub const blue_dim = dim ++ blue;
pub const magenta_dim = dim ++ magenta;
pub const cyan_dim = dim ++ cyan;
pub const white_dim = dim ++ white;

pub const bg_black = "\x1b[40m";
pub const bg_red = "\x1b[41m";
pub const bg_green = "\x1b[42m";
pub const bg_yellow = "\x1b[43m";
pub const bg_blue = "\x1b[44m";
pub const bg_magenta = "\x1b[45m";
pub const bg_cyan = "\x1b[46m";
pub const bg_white = "\x1b[47m";
