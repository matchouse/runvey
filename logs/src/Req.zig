const std = @import("std");
const Allocator = std.mem.Allocator;

const self = @This();

pub const ReqType = enum { accept, recv, close };

req_type: ReqType,
client_fd: i32,
