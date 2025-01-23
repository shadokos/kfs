// Theme Config
pub const theme = struct {
    const cie = @import("colors").cie;

    // Color profile to use.
    // The profile will mainly influence the color matching while converting a gogh theme to vga
    profile: cie.Profile.Items = .D65, // D65 = daylight, sRGB, AdobeRGB

    // 1.0 = replace the old color with the new one when converting a gogh theme to vga
    // 0.5 = blend the old color with the new one equally
    // 0.0 = keep the old color
    background_blend: f32 = 1.0,
    foreground_blend: f32 = 1.0,

    // ΔE2000 weight (default is 1.0, 1.0, 1.0)
    // kL: Lightness weight
    // kC: Chroma weight
    // kH: Hue weight
    k_de: cie.Kde2000 = .{ .L = 1.0, .C = 1.0, .H = 1.0 },

    // The default color diff function to use (default value is CIEDE2000)
    // CIE76: Euclidean distance in the Lab color space, not accurate
    // CIEDE2000:  ΔE2000 color difference formula, more accurate than CIE76
    delta_e: enum { CIE76, CIEDE2000 } = .CIEDE2000,
}{};
