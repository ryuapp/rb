const std = @import("std");
const builtin = @import("builtin");
const trash = @import("trash.zig");
const Output = @import("output.zig").Output;
const clap = @import("clap");

const process = std.process;

const VersionStruct = struct {
    version: []const u8,
};
const RbVersion: VersionStruct = @import("version.zon");

pub fn main() !void {
    try Output.init();
    const alc = std.heap.page_allocator;

    const params = comptime clap.parseParamsComptime(
        \\-f, --force           Ignore nonexistent files and arguments, never prompt
        \\-v, --verbose         Explain what is being done
        \\-h, --help            Display this help and exit.
        \\    --version         Display version information
        \\<str>...              Put FILE(s) and DIRECTORY(ies) in the recycle bin.
    );

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .allocator = alc,
    }) catch {
        const stderr = std.fs.File.stderr();
        var buffer: [4096]u8 = undefined;
        var writer = stderr.writer(&buffer);
        try writer.interface.print("rb: cannot be executed: Invalid arguments\n", .{});
        try writer.interface.flush();
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
            \\  -f, --force           Ignore nonexistent files and arguments, never prompt
            \\  -v, --verbose         Explain what is being done
            \\  -h, --help            Display this help
            \\      --version         Display version information
        ;
        const stderr = std.fs.File.stderr();
        var buffer: [4096]u8 = undefined;
        var writer = stderr.writer(&buffer);
        try writer.interface.print("{s}\n", .{help_message});
        try writer.interface.flush();
        Output.restore();
        process.exit(0);
    }

    // Display version information
    if (res.args.version != 0) {
        const message =
            \\rb {s}
        ;
        const stderr = std.fs.File.stderr();
        var buffer: [4096]u8 = undefined;
        var writer = stderr.writer(&buffer);
        try writer.interface.print(message, .{RbVersion.version});
        try writer.interface.flush();
        Output.restore();
        process.exit(0);
    }

    // No arguments
    if (res.positionals[0].len == 0) {
        const stderr = std.fs.File.stderr();
        var buffer: [4096]u8 = undefined;
        var writer = stderr.writer(&buffer);
        try writer.interface.print("rb: missing operand\nTry 'rb --help' for more information\n", .{});
        try writer.interface.flush();
        Output.restore();
        process.exit(1);
    }

    const verbose = res.args.verbose != 0;
    const force = res.args.force != 0;

    const stderr = std.fs.File.stderr();
    var buffer: [4096]u8 = undefined;
    var stderr_writer = stderr.writer(&buffer);

    for (res.positionals[0]) |filename| {
        const result = try trash.trash(alc, filename);
        // If --force is enabled and file doesn't exist (error code 2) on Windows, ignore it
        if (force and ((comptime builtin.os.tag == .windows) and result == 2)) {
            continue;
        } else if (result != 0) {
            const message = try trash.getErrorMessage(alc, result);
            defer alc.free(message);
            try stderr_writer.interface.print("rb: cannot remove '{s}': {s}\n", .{ filename, message });
            try stderr_writer.interface.flush();
        } else if (verbose) {
            try stderr_writer.interface.print("removed '{s}'\n", .{filename});
            try stderr_writer.interface.flush();
        }
    }
    Output.restore();
    process.exit(0);
}

test {
    _ = trash;
}
