const std = @import("std");
const builtin = @import("builtin");
const windows = @import("windows_trash.zig");

const is_windows = builtin.os.tag == .windows;

pub fn trash(io: std.Io, allocator: std.mem.Allocator, filename: []const u8) !i32 {
    return switch (builtin.os.tag) {
        .windows => windows.trash(io, allocator, filename),
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
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const filename = "test.txt";
    const file = try tmp.dir.createFile(std.testing.io, filename, .{ .read = true });
    file.close(std.testing.io);
    const absolute_path = try tmp.dir.realPathFileAlloc(std.testing.io, filename, std.testing.allocator);
    defer std.testing.allocator.free(absolute_path);

    const result = try trash(std.testing.io, std.testing.allocator, absolute_path);

    try std.testing.expect(result == 0);
}

test "trash directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const directory_name = "TestDir";
    try tmp.dir.createDir(std.testing.io, directory_name, .default_dir);
    const absolute_path = try tmp.dir.realPathFileAlloc(std.testing.io, directory_name, std.testing.allocator);
    defer std.testing.allocator.free(absolute_path);

    const result = try trash(std.testing.io, std.testing.allocator, absolute_path);

    try std.testing.expect(result == 0);
}
