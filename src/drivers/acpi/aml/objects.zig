/// AML object types and runtime values used to populate the ACPI namespace.
///
/// Object type numeric identifiers match those returned by the AML ObjectType()
/// operator (§19.6.96 Table 19.36).
const std = @import("std");

/// Numeric type identifiers returned by the AML ObjectType() operator.
///
/// Values are explicitly assigned to match §19.6.96 Table 19.36.
/// Non-spec variants (index_field_unit, reference) use values >= 0x80 and
/// must be mapped to their spec equivalents before being returned to AML.
pub const ObjectType = enum(u8) {
    uninitialized = 0,
    integer = 1,
    string = 2,
    buffer = 3,
    package = 4,
    field_unit = 5,
    device = 6,
    event = 7,
    method = 8,
    mutex = 9,
    op_region = 10,
    power_resource = 11,
    /// Type 12 is "Reserved" in ACPI 6.4 (§19.6.96 Table 19.36).
    /// DefProcessor (0x5B 0x83) is permanently reserved in ACPI 6.4 (§20.3 Table 20.2).
    /// Kept here only for parsing legacy DSDT/SSDT tables that still use DefProcessor.
    processor = 12,
    thermal_zone = 13,
    buffer_field = 14,
    // Type 15 is "Reserved" in ACPI 6.4 (§19.6.96 Table 19.36).
    debug_object = 16,
    /// IndexField unit: not a distinct ObjectType in the spec (§19.6.96).
    /// Reports as field_unit (5) when the AML ObjectType() operator is called.
    index_field_unit = 0x80,
    /// Internal reference (RefOf, LocalX, ArgX, Index result).
    /// Not exposed via the AML ObjectType() operator.
    reference = 0x81,
    /// BankField unit: not a distinct ObjectType in the spec (§19.6.96).
    /// Reports as field_unit (5) when the AML ObjectType() operator is called.
    bank_field_unit = 0x82,
};

pub const Object = union(ObjectType) {
    uninitialized: void,
    /// AML integer: n-bit little-endian unsigned (§19.3.5 Table 19.5).
    /// 32 bits when Definition Block revision < 2, 64 bits otherwise (§19.3.5 Table 19.5).
    /// Stored as u64 for potential 64-bit table compatibility, but on this 32-bit
    /// kernel (\_REV=1) the executor must mask all results to 32 bits (§5.7.4).
    integer: u64,
    string: []const u8,
    buffer: Buffer,
    package: Package,
    field_unit: FieldUnit,
    device: void,
    event: void,
    method: Method,
    mutex: Mutex,
    op_region: OpRegion,
    power_resource: PowerResource,
    /// See deprecation note on ObjectType.processor.
    processor: Processor,
    thermal_zone: void,
    buffer_field: BufferField,
    debug_object: void,
    index_field_unit: IndexFieldUnit,
    reference: *Object,
    bank_field_unit: BankFieldUnit,

    pub fn to_integer(self: *const Object) ?u64 {
        return switch (self.*) {
            .integer => |v| v,
            else => null,
        };
    }

    /// Return the ACPI spec ObjectType() value for this object (§19.6.96 Table 19.36).
    /// Non-spec variants are mapped to their canonical spec type.
    /// References are followed to return the type of the pointed-to object.
    pub fn spec_type(self: *const Object) u8 {
        return switch (self.*) {
            .index_field_unit => @intFromEnum(ObjectType.field_unit),
            .bank_field_unit => @intFromEnum(ObjectType.field_unit),
            .reference => |ptr| Object.spec_type(ptr),
            else => @intFromEnum(std.meta.activeTag(self.*)),
        };
    }

    pub fn type_name(self: *const Object) []const u8 {
        return @tagName(self.*);
    }
};

/// Control method: executable AML function (§19.6.84, §5.5).
///   ASL: Method (MethodName, NumArgs, SerializeRule, SyncLevel, ...) {TermList}
///   AML: DefMethod := MethodOp PkgLength NameString MethodFlags TermList (§20.2.5.2)
///
/// Up to 7 arguments (Arg0-Arg6) and 8 local variables (Local0-Local7) (§19.6.84).
///
/// MethodFlags := ByteData (§20.2.5.2)
///   bits [2:0]  ArgCount       (0-7)
///   bit  [3]    SerializeFlag  (0=NotSerialized, 1=Serialized)
///   bits [7:4]  SyncLevel      (0x0-0xF)
pub const Method = struct {
    arg_count: u3,
    serialized: bool,
    sync_level: u4,
    /// Slice into the DSDT/SSDT bytecode (not owned).
    code: []const u8,
};

/// Operation region: a region within an address space (§19.6.99, §5.5.2.4).
///   ASL: OperationRegion (RegionName, RegionSpace, Offset, Length)
///   AML: DefOpRegion := OpRegionOp NameString RegionSpace RegionOffset RegionLen (§20.2.5.2)
///
/// RegionOffset and RegionLen are AML TermArg => Integer; stored as u64 here.
/// For SystemIO regions on x86-32, the offset is a 16-bit I/O port address
/// (valid range 0x0000-0xFFFF) and QWordAcc access is not supported.
pub const OpRegion = struct {
    space: AddressSpace,
    offset: u64,
    length: u64,
};

/// Address space identifiers (§19.6.99 Table 5.149).
///   AML: RegionSpace := ByteData (§20.2.5.2)
/// Values 0x00-0x0A are defined by the spec; 0x80-0xFF are OEM-defined.
pub const AddressSpace = enum(u8) {
    system_memory = 0x00,
    system_io = 0x01,
    pci_config = 0x02,
    embedded_controller = 0x03,
    smbus = 0x04,
    system_cmos = 0x05,
    pci_bar_target = 0x06,
    ipmi = 0x07,
    general_purpose_io = 0x08,
    generic_serial_bus = 0x09,
    pcc = 0x0A,
    // 0x0B-0x7E: reserved
    functional_fixed_hw = 0x7F,
    // 0x80-0xFF: OEM defined
    _,
};

/// Field unit: bit-aligned region within an OpRegion (§19.6.47, §5.5.2.4.1).
///   ASL: Field (RegionName, AccessType, LockRule, UpdateRule) {FieldUnitList}
///   AML: DefField := FieldOp PkgLength NameString FieldFlags FieldList (§20.2.5.2)
///
/// FieldFlags := ByteData (§20.2.5.2)
///   bits [3:0]  AccessType  (0=AnyAcc .. 5=BufferAcc)
///   bit  [4]    LockRule    (0=NoLock, 1=Lock)
///   bits [6:5]  UpdateRule  (0=Preserve, 1=WriteAsOnes, 2=WriteAsZeros)
///   bit  [7]    reserved (must be 0)
pub const FieldUnit = struct {
    region_name: [4]u8,
    bit_offset: u32,
    bit_width: u32,
    access_type: AccessType,
    lock_rule: bool,
    update_rule: UpdateRule,
    /// Resolved pointer to the OpRegion node (set during field parsing).
    /// If non-null, used directly instead of searching by region_name.
    region_node: ?*anyopaque = null,
};

/// Index/data field pair: indirect access to a register bank (§19.6.63).
///   ASL: IndexField (IndexName, DataName, AccessType, LockRule, UpdateRule) {FieldUnitList}
///   AML: DefIndexField := IndexFieldOp PkgLength NameString NameString FieldFlags FieldList (§20.2.5.2)
///
/// Reports as ObjectType 5 (field_unit) via the AML ObjectType() operator (§19.6.96).
pub const IndexFieldUnit = struct {
    index_name: [4]u8,
    data_name: [4]u8,
    bit_offset: u32,
    bit_width: u32,
    access_type: AccessType,
    lock_rule: bool,
    update_rule: UpdateRule,
    /// Pre-resolved index field node (set during parse).
    index_node: ?*anyopaque = null,
    /// Pre-resolved data field node (set during parse).
    data_node: ?*anyopaque = null,
};

/// Field access width (§19.6.47 Table 19.33, §19.2.7 AccessTypeKeyword).
///   ASL: AnyAcc | ByteAcc | WordAcc | DWordAcc | QWordAcc | BufferAcc
///   AML: FieldFlags bits [3:0] (§20.2.5.2)
///
/// QWordAcc (64-bit) is valid for SystemMemory but not for SystemIO on x86-32
/// since I/O port accesses are limited to 8/16/32 bits.
pub const AccessType = enum(u4) {
    any = 0,
    byte_access = 1,
    word_access = 2,
    dword_access = 3,
    qword_access = 4,
    buffer_access = 5,
    _,
};

/// Field update rule when a write does not cover the entire access width
/// (§19.6.47 Table 19.34, §19.2.7 UpdateRuleKeyword).
///   ASL: Preserve | WriteAsOnes | WriteAsZeros
///   AML: FieldFlags bits [6:5] (§20.2.5.2)
pub const UpdateRule = enum(u2) {
    preserve = 0,
    write_as_ones = 1,
    write_as_zeros = 2,
    _,
};

/// Buffer field: a bit range within a Buffer object (§19.6.21, §19.3.5 Table 19.5).
///   ASL: CreateField (SourceBuffer, BitIndex, NumBits, FieldName)
///   AML: DefCreateField := CreateFieldOp SourceBuff BitIndex NumBits NameString (§20.2.5.2)
pub const BufferField = struct {
    /// Pointer to the namespace node holding the source Buffer object.
    source_node: *anyopaque,
    bit_offset: u32,
    bit_width: u32,
};

/// Buffer: an array of bytes, uninitialized elements are zero (§19.6.10, §19.3.5 Table 19.5).
///   ASL: Buffer (BufferSize) {Initializer} => Buffer
///   AML: DefBuffer := BufferOp PkgLength BufferSize ByteList (§20.2.5.4)
pub const Buffer = struct {
    data: []u8,
};

/// Package: collection of up to 255 heterogeneous ASL objects (§19.6.101, §19.3.5 Table 19.5).
///   ASL: Package (NumElements) {PackageList} => Package
///   AML: DefPackage := PackageOp PkgLength NumElements PackageElementList (§20.2.5.4)
pub const Package = struct {
    elements: []Object,
};

/// Mutex synchronization object (§19.6.88).
///   ASL: Mutex (MutexName, SyncLevel)
///   AML: DefMutex := MutexOp NameString SyncFlags (§20.2.5.2)
///
/// SyncFlags := ByteData (§20.2.5.2)
///   bits [3:0]  SyncLevel (0x0-0xF)
///   bits [7:4]  reserved (must be 0)
pub const Mutex = struct {
    sync_level: u4,
    owner_depth: u8 = 0,
};

/// Power resource description object (§19.6.107).
///   ASL: PowerResource (ResourceName, SystemLevel, ResourceOrder) {TermList}
///   AML: DefPowerRes := PowerResOp PkgLength NameString SystemLevel ResourceOrder TermList (§20.2.5.2)
///        SystemLevel := ByteData, ResourceOrder := WordData
pub const PowerResource = struct {
    system_level: u8,
    resource_order: u16,
};

/// Bank field unit: banked region within an OpRegion (§19.6.7, §5.5.2.4).
///   ASL: BankField (RegionName, BankName, BankValue, AccessType, LockRule, UpdateRule)
///        {FieldUnitList}
///   AML: DefBankField := BankFieldOp PkgLength NameString NameString BankValue
///        FieldFlags FieldList (§20.2.5.2)
///
/// Accessing a bank field first writes BankValue to the BankName register,
/// then reads/writes the corresponding bit range from the OpRegion.
pub const BankFieldUnit = struct {
    region_name: [4]u8,
    bank_name: [4]u8,
    bank_value: u64,
    bit_offset: u32,
    bit_width: u32,
    access_type: AccessType,
    lock_rule: bool,
    update_rule: UpdateRule,
    region_node: ?*anyopaque = null,
    bank_node: ?*anyopaque = null,
};

/// Processor description object (deprecated: §8.4, §19.2.6 ProcessorTerm).
///   ASL: Processor (ProcessorName, ProcessorID, PBlockAddress, PblockLength) {TermList}
///   AML: ProcessorOp (0x5B 0x83) is Permanently Reserved in ACPI 6.4 (§20.3 Table 20.2).
///        ProcID := ByteData, PblkAddr := DWordData, PblkLen := ByteData (§20.2.5.2)
///
/// Kept only for parsing legacy DSDT/SSDT tables. New firmware must use
/// Device + _HID "ACPI0007" instead (§8.4).
pub const Processor = struct {
    proc_id: u8,
    /// P_BLK I/O port base address (32-bit, x86 I/O space).
    pblk_addr: u32,
    pblk_len: u8,
};
