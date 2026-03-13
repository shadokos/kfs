const std = @import("std");
const colors = @import("colors");
const sdt = @import("sdt.zig");
const osl = @import("../os_layer.zig");
const Registry = @import("registry.zig").Registry;

const log = std.log.scoped(.@"acpi(rdst)");

pub const Error = error{
    invalid_checksum,
    map_failed,
};

/// Parse the RSDT at the given physical address and populate the registry
/// with all referenced SDT entries.
pub fn parse(rsdt_phys: u32, registry: *Registry) !void {
    // First map just the header to read the length
    const hdr = osl.map_object(sdt.SdtHeader, rsdt_phys) catch return Error.map_failed;
    const full_len = hdr.length;
    osl.unmap_memory(@ptrCast(hdr), @sizeOf(sdt.SdtHeader));

    // Now map the full RSDT
    const rsdt_raw = osl.map_memory(rsdt_phys, full_len) catch return Error.map_failed;
    const rsdt_header: *align(1) const sdt.SdtHeader = @ptrCast(rsdt_raw);

    defer osl.unmap_memory(rsdt_raw, full_len);

    // Validate checksum
    if (!rsdt_header.validate()) return Error.invalid_checksum;

    // The RSDT body is an array of 32-bit physical pointers to other SDTs
    const entry_count = (full_len - @sizeOf(sdt.SdtHeader)) / @sizeOf(u32);
    const entries: [*]align(1) const u32 = @ptrCast(rsdt_header.data());

    for (0..entry_count) |i| {
        const entry_phys = entries[i];

        var entry_len: u32 = 0;
        {
            // Map just the header to read signature and length
            const entry_hdr = osl.map_object(sdt.SdtHeader, entry_phys) catch |e| {
                log.warn("RSDT: failed to map entry {d} header at 0x{x}: {s}", .{ i, entry_phys, @errorName(e) });
                continue;
            };
            entry_len = entry_hdr.length;
            osl.unmap_memory(@ptrCast(@constCast(entry_hdr)), @sizeOf(sdt.SdtHeader));
        }

        // 2. On mappe la table entière avec la vraie taille
        const full_entry_raw = osl.map_memory(entry_phys, entry_len) catch |e| {
            log.warn(
                "failed to map full entry {d} at 0x{x} (len {d}): {s}",
                .{ i, entry_phys, entry_len, @errorName(e) },
            );
            continue;
        };
        const entry_hdr: *align(1) const sdt.SdtHeader = @ptrCast(full_entry_raw);

        // On s'assure de libérer la mémoire à la fin de l'itération
        defer osl.unmap_memory(full_entry_raw, entry_len);

        // 3. Maintenant on peut valider le checksum en toute sécurité
        if (entry_hdr.validate()) {
            registry.register(entry_hdr.signature, entry_phys, entry_hdr.length, entry_hdr.revision);
        }
    }
}
