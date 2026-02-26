const std = @import("std");
const os = std.os.linux;
const builtin = @import("builtin");
const config = @import("config.zig");
const heap = std.heap;

const LISTEN_BACKLOG = 128;
const ReqType = enum { accept, recv, close };

const Req = struct { req_type: ReqType, buf: ?[]u8, client_fd: i32 };

var debug_allocator = heap.DebugAllocator(.{ .safety = true }).init;
var keep_running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true);

fn sigHandler(_: i32) callconv(.c) void {
    keep_running.store(false, .monotonic);
}

pub fn main() !void {
    if (builtin.target.os.tag != .linux) {
        @compileError("linux not supported");
    }

    var act = os.Sigaction{
        .handler = .{ .handler = sigHandler },
        .flags = 0,
        .mask = os.sigemptyset(),
    };
    _ = os.sigaction(os.SIG.INT, &act, null);
    _ = os.sigaction(os.SIG.TERM, &act, null);

    const allocator, const is_debug = switch (builtin.mode) {
        .Debug => .{ debug_allocator.allocator(), true },
        else => .{ std.heap.smp_allocator, false },
    };

    defer if (is_debug) {
        if (debug_allocator.deinit() == .leak) unreachable;
    };

    // const config_file = try std.fs.openFileAbsolute("", 0);
    const fd = @as(i32, @intCast(os.socket(os.AF.UNIX, os.SOCK.STREAM, 0)));
    var addr: os.sockaddr.un = undefined;
    addr.family = os.AF.UNIX;
    const socket_path = "/tmp/jxdlogs.sock";
    @memcpy(addr.path[0..socket_path.len], socket_path);

    if (os.unlink(socket_path) == -1) {
        return error.ErrorUnlinkSocket;
    }

    if (os.bind(fd, @ptrCast(&addr), @sizeOf(os.sa_family_t) + socket_path.len) == -1) {
        return error.ErrorBindSocket;
    }
    if (os.listen(fd, LISTEN_BACKLOG) == -1) {
        return error.ErrorListenSocket;
    }

    const flag = os.fcntl(fd, os.F.GETFL, 0);
    if (flag == -1) {
        return error.ErrToGetFileFlag;
    }

    if (os.fcntl(fd, os.F.SETFL, flag | os.SOCK.NONBLOCK) == -1) {
        return error.ErrorSetNonBlock;
    }

    var ring: os.IoUring = try os.IoUring.init(8, 0);
    defer ring.deinit();

    var accept_req = try allocator.create(Req);
    accept_req.req_type = .accept;
    accept_req.buf = null;

    var sqe = try ring.accept(@intFromPtr(accept_req), fd, null, null, 0);

    std.log.info("logs DB started", .{});
    var cqes: [128]os.io_uring_cqe = undefined;
    const wait = 1;
    while (true) {
        if (!keep_running.load(.monotonic)) break;
        _ = ring.submit_and_wait(wait) catch |err| switch (err) {
            error.SignalInterrupt => {
                std.debug.print("submit_and_wait: {}\n", .{err});
                continue;
            },
            else => return err,
        };

        const count = ring.copy_cqes(&cqes, 0) catch |err| switch (err) {
            error.SignalInterrupt => {
                std.debug.print("copy_cqes: {}\n", .{err});
                continue;
            },
            else => return err,
        };

        for (cqes[0..count]) |cqe| {
            const result = cqe.res;
            const completed: *Req = @ptrFromInt(cqe.user_data);

            if (result < 0) {
                std.debug.print("Error code: {d}\n", .{result});
            } else switch (completed.req_type) {
                .accept => {
                    const client_fd = result;

                    var recv_req = try allocator.create(Req);
                    recv_req.buf = try allocator.alloc(u8, 1024);
                    recv_req.req_type = .recv;
                    recv_req.client_fd = client_fd;

                    const recv_buf: os.IoUring.RecvBuffer = .{ .buffer = recv_req.buf.? };

                    sqe = try ring.recv(@intFromPtr(recv_req), client_fd, recv_buf, 0);
                    sqe = try ring.accept(@intFromPtr(completed), fd, null, null, 0);
                },
                .recv => {
                    if (result == 0) {
                        const close_req = try allocator.create(Req);
                        close_req.* = .{ .req_type = .close, .buf = null, .client_fd = completed.client_fd };
                        _ = try ring.close(@intFromPtr(close_req), completed.client_fd);

                        if (completed.buf) |b| {
                            allocator.free(b);
                        }
                        allocator.destroy(completed);
                    } else {
                        const data = completed.buf.?[0..@as(usize, @intCast(result))];
                        std.debug.print("Data received: {s}\n", .{data});
                        const recv_buf: os.IoUring.RecvBuffer = .{ .buffer = completed.buf.? };
                        _ = try ring.recv(@intFromPtr(completed), completed.client_fd, recv_buf, 0);
                    }
                },
                .close => {
                    allocator.destroy(completed);
                },
            }
        }
    }

    std.debug.print("shutdown cleanup started\n", .{});
    allocator.destroy(accept_req);
    std.debug.print("shutdown successfully\n", .{});
}
