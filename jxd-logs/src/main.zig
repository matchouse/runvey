const std = @import("std");
const os = std.os.linux;
const builtin = @import("builtin");
const config = @import("config.zig");
const heap = std.heap;
const assert = std.debug.assert;
const ring_buf = @import("ring_buf.zig");
const freelist = @import("freelist.zig");
const Queue = @import("Queue.zig");

const listen_backlog = 256;
const sq_depth = 256;

var debug_allocator = heap.DebugAllocator(.{ .safety = true }).init;
var keep_running: std.atomic.Value(bool) = .init(true);
var stop_accept = false;

fn sigHandler(_: i32) callconv(.c) void {
    keep_running.store(false, .monotonic);
}

const ReqType = enum { accept, recv, close };

pub const Req = struct { type: ReqType, fd: i32, buf: [4096]u8 = undefined, next: ?*Req = null };

fn push_to_queue(queue: *Queue, item: *Req) void {
    stop_accept = true;
    queue.push(item);
}

pub fn main() !void {
    comptime if (builtin.target.os.tag != .linux) {
        @compileError("only Linux supported");
    };

    var args = std.process.args();
    defer args.deinit();

    _ = args.skip();

    const config_path = args.next().?;

    var act = os.Sigaction{
        .handler = .{ .handler = sigHandler },
        .flags = 0,
        .mask = os.sigemptyset(),
    };
    _ = os.sigaction(os.SIG.INT, &act, null);
    _ = os.sigaction(os.SIG.TERM, &act, null);

    const gpa, const is_debug = switch (builtin.mode) {
        .Debug => .{ debug_allocator.allocator(), true },
        else => .{ std.heap.smp_allocator, false },
    };

    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    std.debug.print("{s}\n", .{config_path});

    const config_file = try std.fs.openFileAbsolute(config_path, .{ .mode = .read_only });
    defer config_file.close();

    var config_file_buf: [1024]u8 = undefined;

    _ = &config_file.reader(&config_file_buf).interface;

    const fd = @as(i32, @intCast(os.socket(os.AF.UNIX, os.SOCK.STREAM, 0)));
    var addr: os.sockaddr.un = undefined;
    addr.family = os.AF.UNIX;
    const socket_path = "/tmp/jxdlogs.sock";
    @memcpy(addr.path[0..socket_path.len], socket_path);

    if (os.bind(fd, @ptrCast(&addr), @sizeOf(os.sa_family_t) + socket_path.len) == -1) {
        return error.BindSocket;
    }
    errdefer _ = os.unlink(socket_path);

    if (os.listen(fd, listen_backlog) == -1) {
        return error.ListenSocket;
    }

    const flag = os.fcntl(fd, os.F.GETFL, 0);
    if (flag == -1) {
        return error.GetFileFlag;
    }

    if (os.fcntl(fd, os.F.SETFL, flag | os.SOCK.NONBLOCK) == -1) {
        return error.SetNonBlock;
    }

    var ring: os.IoUring = try os.IoUring.init(sq_depth, 0);
    defer ring.deinit();

    assert(ring.sq.sqes.len == sq_depth);

    const pool_size = sq_depth * 2;

    var req_pool: freelist.Create(Req, pool_size) = try .init(gpa);
    defer req_pool.deinit(gpa);

    const accept_req = req_pool.get().?;
    defer req_pool.release(accept_req);

    accept_req.* = .{ .type = .accept, .fd = 0 };
    _ = try ring.accept(@intFromPtr(accept_req), fd, null, null, 0);

    std.log.info("logs DB started", .{});

    var cqes: [sq_depth]os.io_uring_cqe = undefined;
    var queue: Queue = .empty;

    const wait = 1;
    while (true) {
        if (!keep_running.load(.monotonic)) break;

        const is_queue_empty = queue.is_empty();
        var remaining_sq = sq_depth - ring.sq_ready();

        if (stop_accept and is_queue_empty and remaining_sq >= sq_depth / 2) {
            _ = try ring.accept(@intFromPtr(accept_req), fd, null, null, 0);
            stop_accept = false;
        }

        if (!is_queue_empty) {
            for (0..remaining_sq) |_| {
                if (queue.pop()) |r| {
                    switch (r.type) {
                        .accept => {
                            _ = try ring.accept(@intFromPtr(r), fd, null, null, 0);
                        },
                        .recv => {
                            const recv_buf: os.IoUring.RecvBuffer = .{ .buffer = &r.buf };
                            _ = try ring.recv(@intFromPtr(r), r.fd, recv_buf, 0);
                        },
                        .close => {
                            _ = try ring.close(@intFromPtr(r), r.fd);
                        },
                    }

                    remaining_sq -= 1;
                }
            }
            if (remaining_sq == 0) stop_accept = true;
        }

        _ = ring.submit_and_wait(wait) catch |err| switch (err) {
            error.SignalInterrupt => continue,
            else => return err,
        };

        const count = ring.copy_cqes(&cqes, 0) catch |err| switch (err) {
            error.SignalInterrupt => continue,
            else => return err,
        };

        for (cqes[0..count]) |cqe| {
            const result = cqe.res;
            const completed: *Req = @ptrFromInt(cqe.user_data);

            if (result < 0) {
                std.debug.print("Error code: {d}\n", .{result});
            } else switch (completed.type) {
                .accept => {
                    const recv_req = req_pool.get() orelse {
                        stop_accept = true;
                        _ = os.close(result);
                        continue;
                    };

                    recv_req.* = .{ .type = .recv, .fd = result };
                    const recv_buf: os.IoUring.RecvBuffer = .{ .buffer = &recv_req.buf };

                    _ = ring.recv(@intFromPtr(recv_req), result, recv_buf, 0) catch
                        push_to_queue(&queue, recv_req);

                    if (!stop_accept) {
                        _ = ring.accept(@intFromPtr(completed), fd, null, null, 0) catch
                            push_to_queue(&queue, completed);
                    }
                },
                .recv => {
                    if (result == 0) {
                        completed.type = .close;
                        completed.buf = undefined;

                        _ = ring.close(
                            @intFromPtr(completed),
                            completed.fd,
                        ) catch push_to_queue(&queue, completed);
                    } else {
                        _ = completed.buf[0..@as(usize, @intCast(result))];

                        const recv_buf: os.IoUring.RecvBuffer = .{ .buffer = &completed.buf };
                        _ = ring.recv(
                            @intFromPtr(completed),
                            completed.fd,
                            recv_buf,
                            0,
                        ) catch push_to_queue(&queue, completed);
                    }
                },
                .close => {
                    req_pool.release(completed);
                },
            }
        }
    }

    std.log.info("shutdown cleanup started", .{});
    _ = os.close(fd);
    _ = os.unlink(socket_path);
    std.log.info("shutdown successfully", .{});
}
