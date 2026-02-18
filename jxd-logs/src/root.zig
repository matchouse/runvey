const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const BLOCK_RAW_SIZE: u32 = 1024 * 64;
// NOTE: no compression on initial version
const COMPRESSION_LVL: u1 = 0;
const VERSION: u8 = 1;

pub const Config = struct {
    data_dir: []const u8,
};

const BlockHeader = packed struct {
    magic: u32,
    version: u16,
    compression: u8,
    flags: u8,
    raw_size: u32,
    compression_size: u32,
    record_count: u32,
    min_ts: i64,
    max_ts: i64,
    crc32: u32,
};

const LogRecordHeader = struct { ts: i64, level: u8, body_size: u32 };

const BlockIndexEntry = struct {
    min_ts: i64,
    max_ts: i64,
    file_offset: u64,
    block_size: u32,
    read_count: u32,
};

const SegmentIndex = struct {
    id: u64,
    blocks: []BlockIndexEntry,
    min_ts: i64,
    max_ts: i64,
};

const StartError = error{RelativePathNotSupported} || fs.File.OpenError || fs.Dir.MakeError;

const Paths = struct { data_dir: fs.Dir, segments: fs.Dir, tmp: fs.Dir };
var data_dir: fs.Dir = undefined;
var segments: fs.Dir = undefined;
var tmp: fs.Dir = undefined;

pub const DB = struct {
    paths: Paths,

    pub fn start(cfg: Config) StartError!void {
        if (!fs.path.isAbsolute(cfg.data_dir)) {
            return StartError.RelativePathNotSupported;
        }

        data_dir = fs.openDirAbsolute(cfg.data_dir, .{}) catch |err| blk: {
            if (err == fs.File.OpenError.FileNotFound) {
                try fs.makeDirAbsolute(cfg.data_dir);
                break :blk try fs.openDirAbsolute(cfg.data_dir, .{});
            }

            return err;
        };

        segments = data_dir.openDir("segments", .{}) catch |err| blk: {
            if (err == fs.File.OpenError.FileNotFound) {
                try data_dir.makeDir("segments");
                break :blk try data_dir.openDir("segments", .{});
            }

            return err;
        };

        tmp = data_dir.openDir("tmp", .{}) catch |err| blk: {
            if (err == fs.File.OpenError.FileNotFound) {
                try data_dir.makeDir("tmp");
                break :blk try data_dir.openDir("tmp", .{});
            }

            return err;
        };
    }
};

// pub fn init(cfg: Config) !void {
//     std.debug.print("{any}\n", cfg);
//     const alloc = std.heap.smp_allocator;
//     var cwd = std.fs.cwd();
//
//     const file = try cwd.openFile("./config.env", .{ .mode = .read_only });
//     defer file.close();
//
//     const bytes = try file.readToEndAlloc(alloc, 1024);
//     defer alloc.free(bytes);
//
//     std.log.info("{d}", .{bytes.len});
//
//     var map = try config.parseConfig(alloc, bytes);
//     defer map.deinit();
//
//     const version = map.get("version").?;
//     std.debug.print("{s}\n", .{version});
//     var configFile = try cwd.openFile("test_db", .{ .mode = .read_write });
//     defer configFile.close();
//
//     var readBuf: [@sizeOf(block_header)]u8 = undefined;
//     var reader = configFile.reader(&readBuf);
//     const stdout_reader = &reader.interface;
//     const readedStrct = try stdout_reader.takeStruct(block_header, .little);
//
//     std.debug.print("{x}\n", .{readedStrct.magic});
//
//     var stdout_buff: [1024]u8 = undefined;
//     var stdout_writer = configFile.writer(&stdout_buff);
//     const stdout_if = &stdout_writer.interface;
//     const data = block_header{
//         .compression = 1,
//         .magic = 0x2020,
//         .version = 1,
//         .compression_size = 1024,
//         .flags = 1,
//         .max_ts = 10,
//         .min_ts = 10,
//         .raw_size = 2048,
//         .record_count = 10,
//     };
//
//     try stdout_if.writeStruct(data, .little);
//     try stdout_if.flush();
// }
