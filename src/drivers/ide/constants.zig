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
    pub const REG_ALT_STATUS: u16 = 0x00;

    pub const CMD_READ_SECTORS: u8 = 0x20;
    pub const CMD_WRITE_SECTORS: u8 = 0x30;
    pub const CMD_IDENTIFY: u8 = 0xEC;
    pub const CMD_IDENTIFY_PACKET: u8 = 0xA1;
    pub const CMD_PACKET: u8 = 0xA0;
    pub const CMD_FLUSH_CACHE: u8 = 0xE7;

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
    pub const CMD_TEST_UNIT_READY: u8 = 0x00;
    pub const CMD_REQUEST_SENSE: u8 = 0x03;
    pub const CMD_READ10: u8 = 0x28;
    pub const CMD_READ_CAPACITY: u8 = 0x25;
    pub const CMD_READ_TOC: u8 = 0x43;
    pub const CMD_GET_CONFIGURATION: u8 = 0x46;
    pub const CMD_READ_DISC_INFO: u8 = 0x51;

    pub const PACKET_SIZE: usize = 12;

    pub const SENSE_NO_SENSE: u8 = 0x00;
    pub const SENSE_NOT_READY: u8 = 0x02;
    pub const SENSE_MEDIUM_ERROR: u8 = 0x03;
    pub const SENSE_HARDWARE_ERROR: u8 = 0x04;
    pub const SENSE_ILLEGAL_REQUEST: u8 = 0x05;
    pub const SENSE_UNIT_ATTENTION: u8 = 0x06;
};
