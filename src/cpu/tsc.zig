const pit = @import("../drivers/pit/pit.zig");
const cpu = @import("../cpu.zig");

pub var calibrated_frequency: u64 = 0;
pub var boot_tsc: u64 = 0;
pub var tsc_per_ms: u64 = 0;
pub var tsc_per_us: u64 = 0;
pub var tsc_per_ns: u64 = 0;

pub fn init() void {
    // Calibration TSC contre PIT pendant boot
    pit.calibrate_tsc();
    boot_tsc = cpu.read_tsc();
}

pub fn get_time_ns() u64 {
    const current_tsc = cpu.read_tsc();
    const tsc_delta = current_tsc - boot_tsc;
    const ns = @divTrunc(@as(u128, tsc_delta) * 1_000_000_000, calibrated_frequency);
    return @intCast(ns);
}

pub fn get_time_us() u64 {
    const current_tsc = cpu.read_tsc();
    const ms = @divTrunc(@as(u128, current_tsc - boot_tsc) * 1_000_000, calibrated_frequency);
    return @intCast(ms);
}

pub fn get_time() u64 {
    const current_tsc = cpu.read_tsc();
    const tsc_delta = current_tsc - boot_tsc;
    return tsc_delta / tsc_per_ms;
}
