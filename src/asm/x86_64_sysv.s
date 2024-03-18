# Transfers execution between coroutines.
#
# Params
#   - rdi: pointer to next stack pointer (*[*]align(8) u8)
#   - rsi: pointer to store current stack pointer (*[*]align(8) u8)
#
.global __zzzcoro_transfer
__zzzcoro_transfer:

/* Save registers to the stack. */
pushq %rbx
pushq %rbp
pushq %r12
pushq %r13
pushq %r14
pushq %r15

/* Store current stack pointer. */
movq %rsp, (%rsi)

/* Set next stack pointer. */
movq (%rdi), %rsp

/* Pop registers from the stack. */
popq %r15
popq %r14
popq %r13
popq %r12
popq %rbp
popq %rbx

/* Transfer into the next coroutine. */
retq



# Entry point for a coroutine.
#
# Params
#   - rdi: pointer to Coro (*Coro)
#   - rbp: pointer to args (?*anyopaque)
#   - rbx: pointer to main function (*const Coro.FnMain aka *const fn (coro: *Coro, args: ?*anyopaque) callconv(.C) noreturn)
#
.global __zzzcoro_start
__zzzcoro_start:

/* Move the args pointer to the correct register for second parameter in ABI */
movq %rbp, %rsi

/* Transfer into main. */
jmpq *%rbx