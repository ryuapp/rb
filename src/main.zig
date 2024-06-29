const std = @import("std");
const trash = @import("trash.zig").trash;

const debug = std.debug;
const process = std.process;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alc = gpa.allocator();
    const args = try process.argsAlloc(alc);

    defer process.argsFree(alc, args);
    if (args.len < 2) {
        debug.print("Usage: gm [FILE]...\ngm: Trash files by Window API.", .{});
        process.exit(2);
    }

    for (args[1..args.len], 0..) |filename, i| {
        if (i > 0)
            debug.print("\n", .{});
        try trash(filename);
    }
    process.exit(0);
}
