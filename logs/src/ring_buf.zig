const std = @import("std");

pub fn init(size: comptime_int, comptime T: type) type {
    if (!std.math.isPowerOfTwo(size)) @compileError("RingBuf size must be power of two");

    return struct {
        buf: [size]T = undefined,
        head: usize = 0,
        tail: usize = 0,

        const Self = @This();

        pub fn is_full(self: *Self) bool {
            const next_head = (self.head + 1) & (size - 1);
            return next_head == self.tail;
        }

        pub fn push(self: *Self, item: T) bool {
            if (self.is_full()) {
                return false;
            }

            self.buf[self.head] = item;
            self.head = (self.head + 1) & (size - 1);
            return true;
        }

        pub fn pop(self: *Self) ?T {
            if (self.head == self.tail) return null;
            const item = self.buf[self.tail];
            self.tail = self.tail + 1;
            return item;
        }
    };
}
