const std = @import("std");
const Req = @import("Req.zig");
const assert = std.debug.assert;

const Self = @This();

head: ?*Req = null,
tail: ?*Req = null,

pub fn push(self: *Self, r: *Req) void {
    assert(r.next == null);

    if (self.tail) |t| {
        t.next = r;
    } else self.head = r;

    self.tail = r;
}

pub fn pop(self: *Self) ?*Req {
    const r = self.head orelse return null;

    self.head = r.next;
    if (self.head == null) self.tail = null;

    return r;
}

pub fn is_empty(self: Self) bool {
    return self.head == null;
}
