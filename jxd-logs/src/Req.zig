const std = @import("std");
const Allocator = std.mem.Allocator;

const self = @This();

pub const ReqType = enum { accept, recv, close, pollin };

req_type: ReqType,
buf: ?[]u8,
client_fd: i32,
next: ?*self = null,

pub fn create(allocator: Allocator, req_type: ReqType, buf_size: u32, client_fd: i32) Allocator.Error!*self {
    const r = try allocator.create(self);
    const buf = if (buf_size > 0) try allocator.alloc(u8, buf_size) else null;
    r.* = .{ .req_type = req_type, .buf = buf, .client_fd = client_fd };
    return r;
}

test "testing Req allocation" {
    const allocator = std.testing.allocator;

    var test_req = try create(allocator, .accept, 0, -1);
    try std.testing.expect(test_req.buf == null);
    try std.testing.expect(test_req.client_fd == -1);
    try std.testing.expect(test_req.req_type == .accept);
    allocator.destroy(test_req);

    test_req = try create(allocator, .recv, 100, -1);
    try std.testing.expect(test_req.req_type == .recv);
    try std.testing.expect(test_req.buf.?.len == 100);
    try std.testing.expect(test_req.buf.?.len == 100);
    if (test_req.buf) |b| allocator.free(b);
    allocator.destroy(test_req);
}
