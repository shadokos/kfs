pub fn Monostate(comptime T: type, comptime value: T) type {
    return packed struct {
        _: enum(T) {
            _State = value,
        } = ._State,
    };
}
