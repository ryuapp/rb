const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const cwd = std.Io.Dir.cwd();

    const tag = init.environ_map.get("RELEASE_TAG") orelse return error.ReleaseTagNotSet;

    const build_zon = try cwd.readFileAlloc(io, "build.zig.zon", allocator, .limited(1024 * 1024));
    defer allocator.free(build_zon);

    const version = try parseVersion(build_zon);
    const expected_tag = try std.fmt.allocPrint(allocator, "v{s}", .{version});
    defer allocator.free(expected_tag);

    if (!std.mem.eql(u8, tag, expected_tag)) {
        std.debug.print("Release tag '{s}' does not match build version '{s}'\n", .{ tag, expected_tag });
        return error.ReleaseVersionMismatch;
    }

    std.debug.print("Release tag '{s}' matches build version\n", .{tag});
}

fn parseVersion(content: []const u8) ![]const u8 {
    const prefix = ".version = \"";
    const start = (std.mem.indexOf(u8, content, prefix) orelse return error.VersionNotFound) + prefix.len;
    const end = std.mem.indexOfPos(u8, content, start, "\"") orelse return error.VersionNotFound;
    return content[start..end];
}
