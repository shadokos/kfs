// GAS: Generic Address Structure

// GAS is a structure used by ACPI to describe the position of registers.
//
// Possible values for AddressSpace are:
//     +--------------+--------------------------------------------------+
//     |    Value     |                  Address Space                   |
//     +--------------+--------------------------------------------------+
//     | 0            | System Memory                                    |
//     | 1            | System I/O                                       |
//     | 2            | PCI Configuration Space                          |
//     | 3            | Embedded Controller                              |
//     | 4            | System Management Bus                            |
//     | 5            | System CMOS                                      |
//     | 6            | PCI Device Bar Target                            |
//     | 7            | IPMI (Intelligent Platform Management Interface) |
//     | 8            | General Purpose I/O                              |
//     | 9            | Generic Serial Bus                               |
//     | 0x0A         | Platform Communications Channel                  |
//     | 0x0B to 0x7F | Reserved                                         |
//     | 0x80 to 0xFF | OEM Defined                                      |
//     +--------------+--------------------------------------------------+

// BitWidth and BitOffset are required only when accessing a bit field.
// AccessSize defines how many bytes can be read or written at once.

pub const GenericAddressStructure = extern struct {
	AddressSpace: u8,
	BitWidth: u8,
	BitOffset: u8,
	AccessSize: u8,
	Address: u64,
};