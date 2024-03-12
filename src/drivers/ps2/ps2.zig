const tty = @import("../../tty/tty.zig");
const ports = @import("../../io/ports.zig");

const ps2_logger = @import("../../ft/ft.zig").log.scoped(.driver_ps2);

// The PS/2 controller driver, is implemented according to osdev.org
// See: https://wiki.osdev.org/%228042%22_PS/2_Controller

// PS/2 I/O Ports:
// ------ Purpose -------|--- Port ---|- Access Type -|
pub const data_port			= 0x60;  //  Read/Write   |
pub const status_register	= 0x64;  //  Read         |
pub const command_register	= 0x64;  //  Write        |

pub const Status = packed struct {
	// (must be set befre attempting to read data from the IO port 0x60)
	output_buffer: u1,
	// (must be clear before attempting to write data to IO port 0x60/0x64)
	input_buffer: u1,
	// (Meant to be cleared on reset and set by firmware
	// (via ps/2 controller configuration byte) if the system passes self tests
	system_flag: u1,
	// (0 = input buffer for ps/2 dveice, 1 = input buffer for ps/2 controller command)
	command: u1,
	// Chipset specific
	unknown: u2,
	// (0 = no error, 1 = timeout error)
	timeout_error: u1,
	// (0 = no error, 1 = parity error)
	parity_error: u1,
};

pub const ControllerConf = packed struct {
	// First PS/2 port interrupt (1 = enabled, 0 = disabled)
	first_port_interrupt: u1,
	// Second PS/2 port interrupt (1 = enabled, 0 = disabled)
	second_port_interrupt: u1,
	// System Flag (1 = system passed POST, 0 = os shouldn't be running)
	system_flag: u1,
	// Should be zero
	zero: u1 = 0,
	// First PS/2 port clock (1 = disabled, 0 = enabled)
	first_port_clock: u1,
	// Second PS/2 port clock (1 = disabled, 0 = enabled)
	second_port_clock: u1,
	// First PS/2 port translation (1 = enabled, 0 = disabled)
	first_port_translation: u1,
	// Must be zero
	zero2: u1 = 0,
};

pub const ControllerOutputPort = packed struct {
	// System reset (output)
	// WARNING: always set to '1', You ned to pulse the reset line (e.g. using command 0xFE),
	// and setting this bit to '0' can lock the computer up ("reset forever")
	system_reset: u1,
	// A20 gate (output)
	a20_gate: u1,
	// Second PS/2 port clock (output, only if 2 PS/2 ports supported)
	second_port_clock: u1,
	// Second PS/2 port data (output, only if 2 PS/2 ports supported)
	second_port_data: u1,
	// Output buffer full with byte from first PS/2 port (connected to IRQ1)
	first_port_buffer_full: u1,
	// Output buffer full with byte from second PS/2 port
	// (connected to IRQ12, only if 2 PS/2 ports supported)
	second_port_buffer_full: u1,
	// First PS/2 port clock (output)
	first_port_clock: u1,
	// First PS/2 port data (output)
	first_port_data: u1,
};

pub const ControllerError = error {
	InvalidResponse,
	ClockLineStuckLow,
	ClockLineStuckHigh,
	DataLineStuckLow,
	DataLineStuckHigh,
};

pub fn get_data() u8 {
	return ports.inb(data_port);
}

pub fn write_data(data: u8) void {
	ports.outb(data_port, data);
}

pub fn get_status() Status {
	return @bitCast(ports.inb(status_register));
}

pub fn get_configuration() ControllerConf {
	send_command(0x20); // Read controller configuration byte
	return @bitCast(get_data());
}

pub fn set_configuration(conf: ControllerConf) void {
	send_command(0x60); // Write controller configuration byte
	write_data(@bitCast(conf));
}

pub fn send_command(command: u8) void {
	ports.outb(command_register, command);
}

pub fn enable_translation() void {
	var conf = get_configuration();
	conf.first_port_translation = 1;
	set_configuration(conf);
}

pub fn enable_first_port() void {
	ps2_logger.debug("\tEnabling first PS/2 port", .{});
	send_command(0xAE);
}

pub fn enable_second_port() void {
	ps2_logger.debug("\tEnabling second PS/2 port", .{});
	send_command(0xA8);
}

pub fn enable_ports() void {
	enable_first_port();
	enable_second_port();
}

pub fn disable_first_port() void {
	send_command(0xAD);
}

pub fn disable_second_port() void {
	send_command(0xA7);
}

pub fn disable_ports() void {
	disable_first_port();
	disable_second_port();
}

pub fn flush_output_buffer() void {
	while (get_status().output_buffer != 0) {
		_ = get_data();
	}
}

pub fn cpu_reset() void {
	ps2_logger.debug("Resetting CPU", .{});

	while (get_status().input_buffer != 0) {}
	send_command(0xFE);
}

pub fn controller_self_test() ControllerError!void {
	ps2_logger.debug("\tPerforming controller self-test", .{});

	// The self-test can reset the ps/2 controller on some hardware
	// so we need to save the controller configuration and restore it after the test
	ps2_logger.debug("\t\tSaving controller configuration", .{});
	var conf = get_configuration();

	send_command(0xAA); // Perform controller self-test
	while (true) {
		var response = get_data();
		switch (response) {
			0x55 => {ps2_logger.debug("\t\tself-test: OK (0x{x:0>2})", .{response}); break;},
			0xFC => {
				ps2_logger.debug("\t\tself-test: KO (0x{x:0>2})", .{response});
				return ControllerError.InvalidResponse;
			},
			else => continue,
		}
	}

	// Restore the controller configuration for hardware compatibility
	ps2_logger.debug("\t\tRestoring controller configuration", .{});
	conf.system_flag = 1;
	set_configuration(conf);
}

pub fn port_test(port: enum {FirstPort, SecondPort}) ControllerError!bool {
	const port_str = if (port == .FirstPort) "first" else "second";
	ps2_logger.debug("\tTesting {s} PS/2 port", .{ port_str });

	send_command(if (port == .FirstPort) 0xAB else 0xA9);
	var response = get_data();

	switch (response) {
		0x00 => ps2_logger.debug("\t\ttest: OK (0x{x:0>2})", .{response}),
		0x01 => {
			ps2_logger.err("\t\t{s} port: (0x{x:0>2} clock line stuck low)", .{port_str, response});
			return ControllerError.ClockLineStuckLow;
		},
		0x02 => {
			ps2_logger.err("\t\t{s} port: (0x{x:0>2} clock line stuck high)", .{port_str, response});
			return ControllerError.ClockLineStuckHigh;
		},
		0x03 => {
			ps2_logger.err("\t\t{s} port: (0x{x:0>2} data line stuck low)", .{port_str, response});
			return ControllerError.DataLineStuckLow;
		},
		0x04 => {
			ps2_logger.err("\t\t{s} port: (0x{x:0>2} data line stuck high)", .{port_str, response});
			return ControllerError.DataLineStuckHigh;
		},
		else => {
			ps2_logger.err("\t\t{s} port: (0x{x:0>2} unknown error)", .{port_str, response});
			return ControllerError.InvalidResponse;
		},
	}
	return true;
}

pub fn init() void {
 	// Will be set to false if the initialization detects it's a single channel controller
	var is_dual_channel = true;

	ps2_logger.debug("Initializing PS/2 Controller", .{});

	// Step 1: Disable PS/2 ports
	ps2_logger.debug("\tDisabling PS/2 ports", .{});
	disable_ports();

	// Step 2: Flush the output buffer
	ps2_logger.debug("\tFlushing the output buffer", .{});
	flush_output_buffer();

	// Step 3: Set the controller configuration byte
	ps2_logger.debug("\tSetting the controller configuration byte", .{});
	var conf = get_configuration();
	{
		ps2_logger.debug("\t\tconfiguration: 0b{b:0>8}", .{@as(u8, @bitCast(conf))});

		ps2_logger.debug("\t\tdisabling interrupts and translation", .{});
		conf.first_port_interrupt = 0;
		conf.second_port_interrupt = 0;
		conf.first_port_translation = 0;
		set_configuration(conf);

		conf = get_configuration();
		ps2_logger.debug("\t\tconfiguration: 0b{b:0>8}", .{@as(u8, @bitCast(conf))});

		// If the second port clock is disabled, then it's a single channel controller
		if (conf.second_port_clock == 0) {
			ps2_logger.debug("\t\tSingle channel controller detected", .{});
			is_dual_channel = false;
		}
	}

	// Step 4: Perform controller self-test
	controller_self_test() catch @panic("PS/2 Controller self-test failed");

	// Step 5: Determine if there are 2 PS/2 ports
	ps2_logger.debug("\tDetermining if it's a dual channel controller", .{});
	if (is_dual_channel) {
		send_command(0xA8); // Enable second PS/2 port
		if (get_configuration().second_port_clock == 1) is_dual_channel = false;
		send_command(0xA7); // Disable second PS/2 port (if available, otherwise ignored)
	}
	if (!is_dual_channel)
		ps2_logger.debug("\t\tSingle channel controller detected", .{})
	else
		ps2_logger.debug("\t\tDual channel controller detected", .{});

	// Step 6: Perform interface Tests
	var available_ports: packed struct {p1: u1 = 0, p2: u1 = 0} = .{};
	{
		available_ports.p1 = @intFromBool(port_test(.FirstPort) catch false);
		if (is_dual_channel)
			available_ports.p2 = @intFromBool(port_test(.SecondPort) catch false);
	}

	// Step 7: Enable PS/2 Ports
	//   Since we're not using interrupt yet, we're not actually able to determine
	//   from which port we're receiving data when polling the status register
	//   So we're only enabling the first port for now assuming it's the keyboard one

	if (available_ports.p1 == 0)
		@panic("PS/2 Controller interface tests failed, first port not working");
	// TODO: When we'll have interrupt support: Remove the above line and uncomment the following lines
	// if (@as(u2, @bitCast(available_ports)) == 0)
	// 	@panic("PS/2 Controller interface tests failed, no working ports detected");

	// if (available_ports.p2 == 1)
	// 	enable_second_port();
	if (available_ports.p1 == 1) {
		enable_translation();
		enable_first_port();
	}
	ps2_logger.info("Controller initialized", .{});
}