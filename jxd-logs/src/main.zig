const std = @import("std");
const os = std.os.linux;
const builtin = @import("builtin");
const config = @import("config.zig");
const heap = std.heap;
const journal = @cImport({
    @cInclude("systemd/sd-journal.h");
});
const Req = @import("Req.zig");
const Queue = @import("Queue.zig");
const assert = std.debug.assert;

const listen_backlog = 128;
const sq_ring_size = 2;

var debug_allocator = heap.DebugAllocator(.{ .safety = true }).init;
var keep_running: std.atomic.Value(bool) = .init(true);

fn sigHandler(_: i32) callconv(.c) void {
    keep_running.store(false, .monotonic);
}

pub fn main() !void {
    if (builtin.target.os.tag != .linux) {
        @compileError("only Linux supported");
    }

    var args = std.process.args();
    defer args.deinit();

    while (args.next()) |arg| {
        std.debug.print("Argument: {s}\n", .{arg});
    }

    var j: ?*journal.sd_journal = null;
    if (journal.sd_journal_open(&j, journal.SD_JOURNAL_LOCAL_ONLY) < 0)
        return error.JounalOpenFailed;

    if (journal.sd_journal_seek_tail(j) < 0)
        return error.JournalSeekTail;

    if (journal.sd_journal_previous(j) < 0)
        return error.JournalNext;

    const log_fd = journal.sd_journal_get_fd(j);
    const journal_events = journal.sd_journal_get_events(j);

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
        _ = debug_allocator.deinit();
    };

    // const config_file = try std.fs.openFileAbsolute("", 0);
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

    var ring: os.IoUring = try os.IoUring.init(sq_ring_size, 0);
    defer ring.deinit();

    assert(ring.sq.sqes.len == sq_ring_size);

    const accept_req = try Req.create(allocator, .accept, 0, -1);
    defer allocator.destroy(accept_req);

    const poll_req = try Req.create(allocator, .pollin, 0, -1);
    defer allocator.destroy(poll_req);

    _ = try ring.accept(@intFromPtr(accept_req), fd, null, null, 0);
    _ = try ring.poll_add(@intFromPtr(poll_req), log_fd, @intCast(journal_events));

    std.log.info("logs DB started", .{});

    var cqes: [sq_ring_size]os.io_uring_cqe = undefined;
    var queue: Queue = .{};

    const wait = 1;
    while (true) {
        if (!keep_running.load(.monotonic)) break;

        if (!queue.is_empty()) {
            const remaining_sq = sq_ring_size - ring.sq_ready();
            for (0..remaining_sq) |_| {
                if (queue.pop()) |r| {
                    switch (r.req_type) {
                        .accept => {
                            _ = try ring.accept(@intFromPtr(r), fd, null, null, 0);
                        },
                        .recv => {
                            const recv_buf: os.IoUring.RecvBuffer = .{ .buffer = r.buf.? };
                            _ = try ring.recv(@intFromPtr(r), r.client_fd, recv_buf, 0);
                        },
                        .close => {
                            _ = try ring.close(@intFromPtr(r), r.client_fd);
                        },
                        .pollin => {
                            _ = try ring.poll_add(@intFromPtr(r), log_fd, @intCast(journal_events));
                        },
                    }
                }
            }
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
            } else switch (completed.req_type) {
                .accept => {
                    const client_fd = result;

                    const recv_req = try Req.create(allocator, .recv, 1024, client_fd);
                    const recv_buf: os.IoUring.RecvBuffer = .{ .buffer = recv_req.buf.? };

                    _ = ring.recv(@intFromPtr(recv_req), client_fd, recv_buf, 0) catch
                        queue.push(recv_req);
                    _ = ring.accept(@intFromPtr(completed), fd, null, null, 0) catch
                        queue.push(completed);
                },
                .recv => {
                    if (result == 0) {
                        const close_req = try Req.create(allocator, .close, 0, completed.client_fd);
                        _ = ring.close(
                            @intFromPtr(close_req),
                            completed.client_fd,
                        ) catch queue.push(close_req);

                        if (completed.buf) |b| allocator.free(b);
                        allocator.destroy(completed);
                    } else {
                        // const data = completed.buf.?[0..@as(usize, @intCast(result))];
                        const recv_buf: os.IoUring.RecvBuffer = .{ .buffer = completed.buf.? };
                        completed.next = null;
                        _ = ring.recv(
                            @intFromPtr(completed),
                            completed.client_fd,
                            recv_buf,
                            0,
                        ) catch queue.push(completed);
                    }
                },
                .close => {
                    allocator.destroy(completed);
                },
                .pollin => {
                    _ = journal.sd_journal_process(j);

                    while (journal.sd_journal_next(j) > 0) {
                        var data_ptr: [*c]const u8 = undefined;
                        var data_len: usize = undefined;

                        if (journal.sd_journal_get_data(
                            j,
                            "MESSAGE",
                            @ptrCast(&data_ptr),
                            &data_len,
                        ) == 0) {
                            const msg = data_ptr[8..data_len];
                            std.debug.print("JOURNAL: {s}\n", .{msg});
                        }
                    }

                    _ = ring.poll_add(
                        @intFromPtr(completed),
                        log_fd,
                        @intCast(journal_events),
                    ) catch queue.push(completed);
                },
            }
        }
    }

    std.log.info("shutdown cleanup started", .{});
    _ = os.unlink(socket_path);
    std.log.info("shutdown successfully", .{});
}
