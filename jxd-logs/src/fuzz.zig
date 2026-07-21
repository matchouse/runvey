const std = @import("std");

// Optional: reduce noise
pub const std_options: std.Options = .{
    .log_level = .err,
};

// Example: simple HTTP-ish parser entry
export fn fuzz_entry(data: [*]const u8, len: usize) void {
    const input = data[0..len];

    // ---- YOUR TARGET LOGIC HERE ----
    // Replace this with your actual parser

    // Example checks (just to create branches)
    if (input.len < 4) return;

    // simulate HTTP parsing paths
    if (std.mem.startsWith(u8, input, "GET")) {
        handleGet(input);
    } else if (std.mem.startsWith(u8, input, "POST")) {
        handlePost(input);
    } else {
        handleOther(input);
    }
}

fn handleGet(input: []const u8) void {
    if (std.mem.indexOf(u8, input, "Host:") != null) {
        // deeper path
        if (std.mem.indexOf(u8, input, "\r\n\r\n") != null) {
            // pretend bug condition (example)
            if (input.len > 10000) {
                @panic("large GET request triggered");
            }
        }
    }
}

fn handlePost(input: []const u8) void {
    if (std.mem.indexOf(u8, input, "Content-Length:") != null) {
        if (input.len > 5000) {
            @panic("large POST triggered");
        }
    }
}

fn handleOther(input: []const u8) void {
    if (input.len > 20000) {
        @panic("unknown large input");
    }
}
