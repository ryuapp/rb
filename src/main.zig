const std = @import("std");
const trash = @import("trash.zig").trash;
const Output = @import("output.zig").Output;
const clap = @import("clap");

const process = std.process;

pub fn main() !void {
    try Output.init();
    const alc = std.heap.page_allocator;

    const params = comptime clap.parseParamsComptime(
        \\-h, --help            Display this help and exit.
        \\<str>...              Put FILE(s) and DIRECTORY(ies) in the recycle bin.
    );

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .allocator = alc,
    }) catch {
        try std.io.getStdErr().writer().print("rb: cannot be executed: Invalid arguments\n", .{});
        Output.restore();
        process.exit(1);
    };
    defer res.deinit();

    // Display help message
    if (res.args.help != 0) {
        const help_message =
            \\Usage: rb [FILE|DIRECTORY]...
            \\Put FILE(s) and DIRECTORY(ies) in the recycle bin.
            \\
            \\Options:
            \\  -h, --help            Display this help
        ;
        try std.io.getStdErr().writer().print("{s}\n", .{help_message});
        Output.restore();
        process.exit(0);
    }

    // No arguments
    if (res.positionals.len == 0) {
        try std.io.getStdErr().writer().print("rb: missing operand\nTry 'rb --help' more information\n", .{});
        Output.restore();
        process.exit(1);
    }

    for (res.positionals) |filename| {
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
