pub const magic: u32 = 0x474f4c4a; // JLOG

pub const SegmentHeader = struct {};

pub const Header = packed struct {
    magic: u32,
    length: u32,
    ts: u64,
    version: u8,
    level: u8,
};
