const GenericAddressStructure = @import("generic_addr_struct.zig").GenericAddressStructure;

pub const FADT = extern struct {
	firmware_ctrl: u32,
	dsdt: u32,

	// field used in ACPI 1.0; no longer in use, for compatibility only
	reserved: u8,

	preferred_power_management_profile: u8,
	sci_interrupt: u16,
	smi_command_port: u32,
	acpi_enable: u8,
	acpi_disable: u8,
	s4bios_req: u8,
	pstate_control: u8,
	pm1a_event_block: u32,
	pm1b_event_block: u32,
	pm1a_control_block: u32,
	pm1b_control_block: u32,
	pm2_control_block: u32,
	pm_timer_block: u32,
	gpe0_block: u32,
	gpe1_block: u32,
	pm1_event_length: u8,
	pm1_control_length: u8,
	pm2_control_length: u8,
	pm_timer_length: u8,
	gpe0_length: u8,
	gpe1_length: u8,
	gpe1_base: u8,
	cstate_control: u8,
	worst_c2_latency: u16,
	worst_c3_latency: u16,
	flush_size: u16,
	flush_stride: u16,
	duty_offset: u8,
	duty_width: u8,
	day_alarm: u8,
	month_alarm: u8,
	century: u8,

	// reserved in ACPI 1.0; used since ACPI 2.0+
	reserved2: u16,
	reserved3: u8,

	flags: u32,

	reset_reg: GenericAddressStructure,

	reset_value: u8,
	reserved4: [3]u8,
};
