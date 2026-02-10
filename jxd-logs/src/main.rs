use std::collections::BTreeMap;

use rkyv::{Archive, Deserialize, Serialize};

mod reader;
mod writer;

const BLOCK_RAW_SIZE: u32 = 1 * 1024 * 1024;
const COMPRESSION_LVL: u8 = 1;

#[derive(Archive, Deserialize, Serialize, Debug, PartialEq)]
#[rkyv(compare(PartialEq), derive(Debug))]
#[repr(C)]
pub struct BlockHeader {
    pub magic: u32,
    pub version: u16,
    pub compression: u8,
    pub flags: u8,
    pub raw_size: u32,
    pub cmp_len: u32,
    pub record_count: u32,
    pub min_ts: i64,
    pub max_ts: i64,
    pub crc32: u32,
}

#[repr(C)]
pub struct LogRecordHeader {
    pub ts: i64,
    pub level: u8,
    pub body_len: u32,
}

pub struct BlockIndexEntry {
    pub min_ts: i64,
    pub max_ts: i64,
    pub file_offset: u64,
    pub block_size: u32,
    pub record_count: u32,
}

pub struct SegmentIndex {
    pub segment_id: u64,
    pub blocks: Vec<BlockIndexEntry>,
    pub min_ts: i64,
    pub max_ts: i64,
}

pub struct GlobalIndex {
    pub segments: BTreeMap<u64, SegmentIndex>,
}

fn main() {
    println!("Hello, world!");
}
