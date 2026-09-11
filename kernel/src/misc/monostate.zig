// A type that can only be assigned one value
pub fn Monostate(comptime T: type, comptime value: T) type {
    return packed struct(T) {
        _: enum(T) {
            _State = value,
        } = ._State,
    };
}
