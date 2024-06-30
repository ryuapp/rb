const std = @import("std");
const trash = @import("trash.zig").trash;

const process = std.process;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alc = gpa.allocator();
    const args = try process.argsAlloc(alc);

    defer process.argsFree(alc, args);
    if (args.len < 2) {
        try std.io.getStdErr().writer().print("Usage: gm [FILE|DIRECTORY]...\nPut FILE(s) and DIRECTORY(ies) in the recycle bin.", .{});
        process.exit(2);
    }

    var before_result: c_int = 0;
    for (args[1..args.len], 0..) |filename, i| {
        if (i > 0) {
            switch (before_result) {
                0 => try std.io.getStdOut().writer().print("\n", .{}),
                else => try std.io.getStdErr().writer().print("\n", .{}),
            }
        }
        before_result = try trash(filename);
    }
    process.exit(0);
}
