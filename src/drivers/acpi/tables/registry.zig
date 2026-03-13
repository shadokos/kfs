const std = @import("std");
const colors = @import("colors");
const sdt = @import("sdt.zig");
const osl = @import("../os_layer.zig");

const log = std.log.scoped(.@"acpi(registry)");

// MAX_TABLES is an arbitrary limit on how many tables we can track.
// Most systems will have fewer than 20,
// this limitation just prevents unbounded memory usage if something goes wrong during discovery.
pub const MAX_TABLES = 64;

// Note:
// TableEntry doesn't represent an actual SDT header,
// instead it just tracks the signature, physical address and length of discovered tables.
pub const TableEntry = struct {
    signature: [4]u8,
    physical_address: u32,
    length: u32,
    revision: u8,
};

// Registry of discovered ACPI tables
// This is populated during table discovery and allows other code to find tables by signature and map them as needed.
// We don't need complex data structures here since the number of tables is small and lookups are infrequent,
// so we just use a simple array.
pub const Registry = struct {
    entries: [MAX_TABLES]TableEntry = undefined,
    count: usize = 0,

    /// Register a newly discovered table.
    pub fn register(self: *Registry, sig: [4]u8, phys: u32, length: u32, revision: u8) void {
        if (self.count >= MAX_TABLES) {
            log.warn("Table registry full, ignoring {s}", .{sig});
            return;
        }
        self.entries[self.count] = .{
            .signature = sig,
            .physical_address = phys,
            .length = length,
            .revision = revision,
        };
        self.count += 1;
    }

    /// Register a table by its physical address.
    /// Maps the header, extracts info, and registers it.
    pub fn register_address(self: *Registry, phys: u32) !void {
        const header = try osl.map_object(sdt.SdtHeader, phys);
        defer osl.unmap_memory(@ptrCast(@constCast(header)), @sizeOf(sdt.SdtHeader));

        self.register(
            header.signature,
            phys,
            header.length,
            header.revision,
        );
    }

    /// Find the first table matching a 4-char signature.
    pub fn find(self: *const Registry, sig: [4]u8) ?*const TableEntry {
        for (self.entries[0..self.count]) |*entry| {
            if (std.mem.eql(u8, &entry.signature, &sig)) return entry;
        }
        return null;
    }

    /// Count tables matching a signature.
    pub fn count_sig(self: *const Registry, sig: [4]u8) usize {
        var n: usize = 0;
        for (self.entries[0..self.count]) |*entry| {
            if (std.mem.eql(u8, &entry.signature, &sig)) n += 1;
        }
        return n;
    }

    /// Map a table entry and return a pointer to its SDT header.
    /// The caller is responsible for unmapping when done.
    pub fn map_table(entry: *const TableEntry) !*align(1) const sdt.SdtHeader {
        const ptr = try osl.map_memory(entry.physical_address, entry.length);
        return @ptrCast(ptr);
    }

    /// Map a table and validate its checksum. Returns null on failure.
    pub fn map_and_validate(entry: *const TableEntry, comptime _: []const u8) !*align(1) const sdt.SdtHeader {
        const header = try map_table(entry);
        if (!header.validate()) {
            osl.unmap_memory(@ptrCast(@constCast(header)), entry.length);
            return error.invalid_checksum;
        }
        return header;
    }

    /// Map and validate a table entry, then cast its data to T.
    /// T must include the SdtHeader as its first field.
    pub fn map_typed_entry(entry: *const TableEntry, comptime name: []const u8, comptime T: type) !*align(1) const T {
        const header = try map_and_validate(entry, name);
        return @ptrCast(header);
    }

    /// Map and validate a table entry, and return its AML data (bytecode).
    pub fn map_aml_entry(entry: *const TableEntry, comptime name: []const u8) ![]const u8 {
        const header = try map_typed_entry(entry, name, sdt.SdtHeader);
        return header.data()[0..header.data_len()];
    }

    /// Find, map and validate a table, then cast its data to T.
    pub fn map_typed(self: *const Registry, comptime sig: [4]u8, comptime T: type) !*align(1) const T {
        const entry = self.find(sig) orelse return error.table_not_found;
        return map_typed_entry(entry, &sig, T);
    }

    /// Find, map and validate a table, and return its AML data (bytecode).
    pub fn map_aml(self: *const Registry, comptime sig: [4]u8) ![]const u8 {
        const entry = self.find(sig) orelse return error.table_not_found;
        return map_aml_entry(entry, &sig);
    }

    /// Iterate over all entries (for enumeration / debug).
    pub fn iter(self: *const Registry) []const TableEntry {
        return self.entries[0..self.count];
    }

    /// Log summary of all registered tables.
    pub fn log_summary(self: *const Registry) void {
        log.info("Table registry: {d} tables discovered", .{self.count});
        for (self.entries[0..self.count]) |entry| {
            log.debug(
                "  {s}  phys=0x{x:0>8}  len={d}  rev={d}",
                .{ entry.signature, entry.physical_address, entry.length, entry.revision },
            );
        }
    }
};
