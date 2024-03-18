const std = @import("std");
const assert = std.debug.assert;

const stack_alignment = 16;

pub const Coro = extern struct {
    stack_pointer: [*]align(8) u8,

    pub const FnMain = fn (this_coro: *Coro, arg: ?*anyopaque) callconv(.C) noreturn;

    pub fn init(
        stack: []align(stack_alignment) u8,
        main: *const FnMain,
        arg: ?*anyopaque,
    ) Coro {
        const register_space = 8 * @sizeOf(usize);

        assert(stack.len >= register_space);
        assert(stack.len % stack_alignment == 0);

        // Note that we store the pointer to __zzzcoro_start at an even index, which means
        // that after returning from __zzzcoro_transfer, the stack will not be aligned
        // to 16 bytes. This is fine because for the initial transfer we (mis)use the retq instruction
        // to actually perform a call, and any function conforming to ABI expects the stack
        // to not be aligned to 16 at the start of the function.
        const registers: []usize = @alignCast(std.mem.bytesAsSlice(usize, stack[stack.len - register_space ..]));
        @memset(registers, undefined);
        registers[0] = @intFromPtr(arg); // r15
        registers[1] = @intFromPtr(main); // r14
        registers[6] = @intFromPtr(&__zzzcoro_start);
        return .{ .stack_pointer = @ptrCast(registers.ptr) };
    }

    pub inline fn transferFrom(to: *Coro, from: *Coro) void {
        __zzzcoro_transfer(&to.stack_pointer, &from.stack_pointer);
    }
    pub inline fn transferTo(from: *Coro, to: *Coro) void {
        __zzzcoro_transfer(&to.stack_pointer, &from.stack_pointer);
    }
};

extern fn __zzzcoro_start(sp: *[*]align(8) u8, _: *[*]align(8) u8) noreturn;
extern fn __zzzcoro_transfer(sp_next: *[*]align(8) u8, sp: *[*]align(8) u8) void;
comptime {
    asm (@embedFile("asm/x86_64.s"));
}

test {
    const testing = std.testing;

    const global = struct {
        var main: Coro = undefined;
    };

    const run = struct {
        fn run(this_coro: *Coro, arg: ?*anyopaque) callconv(.C) noreturn {
            const counter: *i32 = @alignCast(@ptrCast(arg.?));
            counter.* += 1;
            global.main.transferFrom(this_coro);
            unreachable;
        }
    }.run;

    var counter: i32 = 0;

    var mem: [4096]u8 align(16) = undefined;

    var coro = Coro.init(&mem, run, &counter);
    global.main.transferTo(&coro);
    try testing.expectEqual(@as(i32, 1), counter);
}
