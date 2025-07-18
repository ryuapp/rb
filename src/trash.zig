const std = @import("std");
const builtin = @import("builtin");
const windows = @import("windows_trash.zig");

const is_windows = builtin.os.tag == .windows;

pub fn trash(allocator: std.mem.Allocator, filename: []const u8) !i32 {
    return switch (builtin.os.tag) {
        .windows => windows.trash(allocator, filename),
        else => error.UnsupportedPlatform,
    };
}

pub fn getErrorMessage(allocator: std.mem.Allocator, error_code: i32) ![]const u8 {
    return switch (builtin.os.tag) {
        .windows => windows.getErrorMessage(allocator, error_code),
        else => try std.fmt.allocPrint(allocator, "Error Code: {d}", .{error_code}),
    };
}

test "trash file" {
    const filename = "test.txt";
    _ = try std.fs.cwd().createFile(
        filename,
        .{ .read = true },
    );

    const result = try trash(std.testing.allocator, filename);

    try std.testing.expect(result == 0);
}

test "trash directory" {
    const directory_name = "TestDir";
    try std.fs.cwd().makeDir(directory_name);

    const result = try trash(std.testing.allocator, directory_name);

    try std.testing.expect(result == 0);
}
