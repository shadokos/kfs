const core = @import("../core.zig");
const BlockDevice = core.BlockDevice;

const Self = @This();

/// Interface pour les fournisseurs de dispositifs
vtable: *const VTable,
context: *anyopaque,

pub const VTable = struct {
    /// Découverte automatique (retourne le nombre de devices trouvés)
    discover: *const fn (ctx: *anyopaque) u32,

    /// Créer un dispositif avec paramètres
    create: *const fn (ctx: *anyopaque, params: *const void) anyerror!*BlockDevice,

    /// Nettoyer les ressources du provider
    deinit: *const fn (ctx: *anyopaque) void,
};

pub fn discover(self: *Self) u32 {
    return self.vtable.discover(self.context);
}

pub fn create(self: *Self, params: *const void) !*BlockDevice {
    return self.vtable.create(self.context, params);
}

pub fn deinit(self: *Self) void {
    self.vtable.deinit(self.context);
}
