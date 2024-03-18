const impl = @import("./x86_64.zig");

pub const Coro = impl.Coro;

comptime {
    _ = Coro;
}
