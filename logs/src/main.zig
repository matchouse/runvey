const std = @import("std");
const os = std.os.linux;
const builtin = @import("builtin");
const config = @import("config.zig");
const heap = std.heap;
const assert = std.debug.assert;
const ring_buf = @import("ring_buf.zig");
const freelist = @import("freelist.zig");
const Queue = @import("Queue.zig");
const proto = @import("proto.zig");

const listen_backlog = 256;
const sq_depth = 256;

var debug_allocator = heap.DebugAllocator(.{ .safety = true }).init;
var keep_running: std.atomic.Value(bool) = .init(true);
var stop_accept = false;

fn sigHandler(_: os.SIG) callconv(.c) void {
    keep_running.store(false, .monotonic);
}

const ReqOperation = enum { accept, recv, close, timer };

const buf_size = 4096;
const header_size = 10;

pub const Req = struct {
    operation: ReqOperation,
    fd: i32,
    position: u16 = 0,
    buf: [buf_size]u8 = undefined,
    next: ?*Req = null,
};

fn push_to_queue(queue: *Queue, item: *Req) void {
    stop_accept = true;
    queue.push(item);
}

fn ToPacked(comptime T: type) type {
    const info = @typeInfo(T).@"struct";
    const names = std.meta.fieldNames(T);

    const types: [names.len]type = blk: {
        var t_arr: [names.len]type = undefined;
        for (info.fields, 0..) |f, i| {
            t_arr[i] = f.type;
        }
        break :blk t_arr;
    };

    return @Struct(
        .@"packed", // Force the packed layout
        null, // No specific backing integer
        names,
        &types,
        &@splat(.{}), // Apply default attributes (alignment, etc) to all fields
    );
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    if (args.len == 1) {
        return error.ConfigRequired;
    }

    const config_path = args[1];

    var act = os.Sigaction{
        .handler = .{ .handler = sigHandler },
        .flags = 0,
        .mask = os.sigemptyset(),
    };
    _ = os.sigaction(os.SIG.INT, &act, null);
    _ = os.sigaction(os.SIG.TERM, &act, null);

    std.debug.print("{s}\n", .{config_path});

    const config_file = try std.Io.Dir.openFileAbsolute(io, config_path, .{ .mode = .read_only });
    defer config_file.close(io);

    var config_file_buf: [1024]u8 = undefined;

    _ = &config_file.reader(io, &config_file_buf).interface;

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

    accept_req.* = .{ .operation = .accept, .fd = 0 };
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
                    switch (r.operation) {
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
                        .timer => {},
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
            } else switch (completed.operation) {
                .accept => {
                    const recv_req = req_pool.get() orelse {
                        stop_accept = true;
                        _ = os.close(result);
                        continue;
                    };

                    recv_req.* = .{ .operation = .recv, .fd = result };
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
                        completed.operation = .close;
                        completed.buf = undefined;

                        _ = ring.close(
                            @intFromPtr(completed),
                            completed.fd,
                        ) catch push_to_queue(&queue, completed);
                    } else {
                        const new_position: u16 = @intCast(completed.position + result);
                        std.debug.print("full buf - {s}\n", .{completed.buf});
                        const data = completed.buf[completed.position..new_position];
                        completed.position = if (new_position >= buf_size) 0 else new_position;

                        std.debug.print("current buf - {s}\n", .{data});

                        const recv_buf: os.IoUring.RecvBuffer = .{ .buffer = completed.buf[completed.position..] };
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
                .timer => {},
            }
        }
    }

    std.log.info("shutdown cleanup started", .{});
    _ = os.close(fd);
    _ = os.unlink(socket_path);
    std.log.info("shutdown successfully", .{});
}

test "packed struct size should equal to header_size" {
    const Header = ToPacked(proto.Header);

    std.debug.print("{} {}\n", .{ @sizeOf(Header), @sizeOf(proto.Header) });
}
