pub const ATA = struct {
    pub const REG_DATA: u16 = 0x00;
    pub const REG_ERROR_READ: u16 = 0x01;
    pub const REG_FEATURES: u16 = 0x01;
    pub const REG_SEC_COUNT: u16 = 0x02;
    pub const REG_LBA_LOW: u16 = 0x03;
    pub const REG_LBA_MID: u16 = 0x04;
    pub const REG_LBA_HIGH: u16 = 0x05;
    pub const REG_DEVICE: u16 = 0x06;
    pub const REG_STATUS: u16 = 0x07;
    pub const REG_COMMAND: u16 = 0x07;

    pub const SELECT_MASTER: u8 = 0xA0;
    pub const SELECT_SLAVE: u8 = 0xB0;

    pub const CMD_READ_SECTORS: u8 = 0x20;
    pub const CMD_WRITE_SECTORS: u8 = 0x30;
    pub const CMD_IDENTIFY: u8 = 0xEC;
    pub const CMD_IDENTIFY_PACKET: u8 = 0xA1;
    pub const CMD_PACKET: u8 = 0xA0;

    // Legacy Controller IO Ports & IRQs
    pub const PRIMARY_BASE: u16 = 0x1F0;
    pub const PRIMARY_CTRL: u16 = 0x3F6;
    pub const PRIMARY_IRQ: u8 = 14;

    pub const SECONDARY_BASE: u16 = 0x170;
    pub const SECONDARY_CTRL: u16 = 0x376;
    pub const SECONDARY_IRQ: u8 = 15;

    // Device Control Register bits
    // Software Reset:
    //  - Sends a reset signal to each drive on the bus (both master and slave)
    pub const CTRL_SRST: u8 = 0x04;

    pub const STATUS_BUSY: u8 = 0x80;
    pub const STATUS_READY: u8 = 0x40;
    pub const STATUS_WRITE_FAULT: u8 = 0x20;
    pub const STATUS_SEEK_COMPLETE: u8 = 0x10;
    pub const STATUS_DRQ: u8 = 0x08;
    pub const STATUS_CORRECTED: u8 = 0x04;
    pub const STATUS_IDX: u8 = 0x02;
    pub const STATUS_ERROR: u8 = 0x01;

    pub const ERROR_BAD_BLOCK: u8 = 0x80;
    pub const ERROR_UNCORRECTABLE: u8 = 0x40;
    pub const ERROR_MEDIA_CHANGED: u8 = 0x20;
    pub const ERROR_ID_MARK_NOT_FOUND: u8 = 0x10;
    pub const ERROR_MEDIA_CHANGE_REQ: u8 = 0x08;
    pub const ERROR_CMD_ABORTED: u8 = 0x04;
    pub const ERROR_TRACK0_NOT_FOUND: u8 = 0x02;
    pub const ERROR_ADDR_MARK_NOT_FOUND: u8 = 0x01;
};

pub const ATAPI = struct {
    pub const CMD_READ10: u8 = 0x28;
    pub const CMD_READ_CAPACITY: u8 = 0x25;

    pub const PACKET_SIZE: usize = 12;

    pub const SIGNATURE_MID: u8 = 0x14;
    pub const SIGNATURE_HIGH: u8 = 0xEB;
};

pub const SCSI = struct {
    pub const Read10 = packed struct {
        opcode: u8,
        reserved1: u8,
        lba: u32,
        reserved2: u8,
        transfer_len: u16,
        control: u8,
        pad: u16, // Padding to 12 bytes
    };

    pub const ReadCapacity = packed struct {
        opcode: u8,
        reserved1: u8,
        lba: u32,
        reserved2: u16,
        pmi: u8, // Partial Medium Indicator
        control: u8, // Control
        pad: u16, // Padding to 12 bytes
    };
};
