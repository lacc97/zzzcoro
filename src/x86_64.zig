const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;

const stack_alignment = 16;

const abi: Abi = if (builtin.os.tag == .windows) .{
    // rbx, rbp, rdi, rsi, rsp, r12-15 + xmm6-xmm15
    .words_saved = 9 + 2 * 10,
} else .{
    // rbx, rbp, r12-15
    .words_saved = 6,
    .assembly = @embedFile("asm/x86_64_sysv.s"),
};

pub const Coro = extern struct {
    stack_pointer: [*]align(8) u8,

    pub const FnMain = fn (this_coro: *Coro, arg: ?*anyopaque) callconv(.C) noreturn;

    pub fn init(
        stack: []align(stack_alignment) u8,
        coro_main: *const FnMain,
        arg: ?*anyopaque,
    ) Coro {
        // Add 1 for rip and then align to next multiple of 2.
        const register_space = ((abi.words_saved + 3) & ~@as(usize, 1));

        assert(stack.len >= 8 * register_space);
        assert(stack.len % stack_alignment == 0);

        // Note that we store the pointer to __zzzcoro_start at an even index, which means
        // that after returning from __zzzcoro_transfer, the stack will not be aligned
        // to 16 bytes. This is fine because for the initial transfer we (mis)use the retq instruction
        // to actually perform a call, and any function conforming to ABI expects the stack
        // to not be aligned to 16 at the start of the function.
        const registers: []usize = @alignCast(std.mem.bytesAsSlice(usize, stack[stack.len - 8 * register_space ..]));
        @memset(registers, undefined);
        registers[register_space - 4] = @intFromPtr(arg);
        registers[register_space - 3] = @intFromPtr(coro_main);
        registers[register_space - 2] = @intFromPtr(&__zzzcoro_start);
        return .{ .stack_pointer = @ptrCast(registers.ptr) };
    }

    pub inline fn transferFrom(to: *Coro, from: *Coro) void {
        __zzzcoro_transfer(&to.stack_pointer, &from.stack_pointer);
    }
    pub inline fn transferTo(from: *Coro, to: *Coro) void {
        __zzzcoro_transfer(&to.stack_pointer, &from.stack_pointer);
    }
};

const Abi = struct {
    // Does not count rip.
    words_saved: usize,

    assembly: []const u8,
};

extern fn __zzzcoro_start(sp: *[*]align(8) u8, _: *[*]align(8) u8) noreturn;
extern fn __zzzcoro_transfer(sp_next: *[*]align(8) u8, sp: *[*]align(8) u8) void;
comptime {
    asm (abi.assembly);
}

test {
    const testing = std.testing;

    const global = struct {
        var main_coro: Coro = undefined;
    };

    const run = struct {
        fn run(this_coro: *Coro, arg: ?*anyopaque) callconv(.C) noreturn {
            const counter: *i32 = @alignCast(@ptrCast(arg.?));
            counter.* += 1;
            global.main_coro.transferFrom(this_coro);
            unreachable;
        }
    }.run;

    var counter: i32 = 0;

    var mem: [4096]u8 align(16) = undefined;

    var coro = Coro.init(&mem, run, &counter);
    global.main_coro.transferTo(&coro);
    try testing.expectEqual(@as(i32, 1), counter);
}
