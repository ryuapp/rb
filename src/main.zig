const std = @import("std");
const trash = @import("trash.zig").trash;
const Output = @import("output.zig").Output;

const process = std.process;

pub fn main() !void {
    try Output.init();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alc = gpa.allocator();
    const args = try process.argsAlloc(alc);

    defer process.argsFree(alc, args);
    if (args.len < 2) {
        try std.io.getStdErr().writer().print("Usage: rb [FILE|DIRECTORY]...\nPut FILE(s) and DIRECTORY(ies) in the recycle bin.\n", .{});
        Output.restore();
        process.exit(2);
    }

    for (args[1..args.len]) |filename| {
        const result = try trash(filename);
        const message: []const u8 = switch (result) {
            2 => "Not found",
            5 => "Access denied",
            32 => "The process cannot access the file because it is being used by another process",
            else => "",
        };

        const prefix_msg: []const u8 = "rb: cannot remove";
        if (message.len > 0) {
            try std.io.getStdErr().writer().print("{s} '{s}': {s}\n", .{ prefix_msg, filename, message });
        } else if (result != 0) {
            try std.io.getStdErr().writer().print("{s} '{s}': Error code: {d}\n", .{ prefix_msg, filename, result });
        }
    }
    Output.restore();
    process.exit(0);
}
