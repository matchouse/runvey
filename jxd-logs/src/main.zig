const std = @import("std");
const jxd_logs = @import("jxd_logs_zig");

pub fn main() !void {
    try jxd_logs.DB.start(.{ .data_dir = "/home/vijay/.jxd_logs_data" });
}
