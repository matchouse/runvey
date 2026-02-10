const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const config = @import("config.zig");
const Io = std.Io;

const BLOCK_RAW_SIZE: u32 = 1 * 1024 * 1024;
const COMPRESSION_LVL: u1 = 1;
const VERSION: u8 = 1;

pub const Config = struct {
    data_dir: []const u8,
};

const block_header = packed struct {
    magic: u32,
    version: u16,
    compression: u8,
    flags: u8,
    raw_size: u32,
    compression_size: u32,
    record_count: u32,
    min_ts: i64,
    max_ts: i64,
};

const log_record_header = struct { ts: i64, level: u8, body_size: u32 };

pub fn init(cfg: Config) !void {
    std.debug.print("{any}\n", cfg);
    const alloc = std.heap.smp_allocator;
    var cwd = std.fs.cwd();

    const file = try cwd.openFile("./config.env", .{ .mode = .read_only });
    defer file.close();

    const bytes = try file.readToEndAlloc(alloc, 1024);
    defer alloc.free(bytes);

    std.log.info("{d}", .{bytes.len});

    var map = try config.parseConfig(alloc, bytes);
    defer map.deinit();

    const version = map.get("version").?;
    std.debug.print("{s}\n", .{version});
    var configFile = try cwd.openFile("test_db", .{ .mode = .read_write });
    defer configFile.close();

    var readBuf: [@sizeOf(block_header)]u8 = undefined;
    var reader = configFile.reader(&readBuf);
    const stdout_reader = &reader.interface;
    const readedStrct = try stdout_reader.takeStruct(block_header, .little);

    std.debug.print("{x}\n", .{readedStrct.magic});

    var stdout_buff: [1024]u8 = undefined;
    var stdout_writer = configFile.writer(&stdout_buff);
    const stdout_if = &stdout_writer.interface;
    const data = block_header{
        .compression = 1,
        .magic = 0x2020,
        .version = 1,
        .compression_size = 1024,
        .flags = 1,
        .max_ts = 10,
        .min_ts = 10,
        .raw_size = 2048,
        .record_count = 10,
    };

    try stdout_if.writeStruct(data, .little);
    try stdout_if.flush();
}
