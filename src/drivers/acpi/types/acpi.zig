const FADT = @import("fadt.zig").FADT;
pub const ACPI = extern struct {
	SMI_CMD: *align(1) u32 = undefined,
	ACPI_ENABLE: *align(1) u8 = undefined,
	ACPI_DISABLE: *align(1) u8 = undefined,
	PM1a_CNT: u32 = 0,
	PM1b_CNT: u32 = 0,
	SLP_TYPa: u16 = 0,
	SLP_TYPb: u16 = 0,
	SLP_EN: u16 = 1 << 13,
	SCI_EN: u16 = 1,
	PM1_CNT_LEN: u8 = 0,
	fadt: *align(1) FADT = undefined,
};