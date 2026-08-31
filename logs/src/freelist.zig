const std = @import("std");

pub fn Create(comptime T: type, size: comptime_int) type {
    if (!std.math.isPowerOfTwo(size)) @compileError("free_list size must be power of two");

    return struct {
        const Self = @This();

        free_list: [size]u16 = undefined,
        free_top: u16 = size,
        data: []T = undefined,

        pub const empty: Self = .{};

        pub fn init(gpa: std.mem.Allocator) !Self {
            var self: Self = .empty;

            for (0..size) |i| self.free_list[i] = @intCast(i);
            self.data = try gpa.alloc(T, size);

            return self;
        }

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            gpa.free(self.data);
        }

        pub fn get(self: *Self) ?*T {
            if (self.free_top == 0) return null;

            self.free_top -= 1;
            const free = self.free_list[self.free_top];
            return &self.data[free];
        }

        pub fn release(self: *Self, item: *T) void {
            std.debug.assert(self.free_top + 1 <= size);

            const idx = item - self.data.ptr;
            self.free_list[self.free_top] = @intCast(idx);
            self.free_top += 1;
        }

        pub fn available(self: *Self) u16 {
            return self.free_top;
        }
    };
}
