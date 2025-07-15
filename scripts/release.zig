const std = @import("std");
const fs = std.fs;
const process = std.process;
const io = std.io;
const json = std.json;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read build.zig.zon
    const build_zon_content = try fs.cwd().readFileAlloc(allocator, "build.zig.zon", 1024 * 1024);
    defer allocator.free(build_zon_content);

    // Parse version from build.zig.zon
    const version = try parseVersion(allocator, build_zon_content);
    defer allocator.free(version);

    // Write version.zon
    try writeVersionZon(allocator, version);

    // Format version.zon
    try formatVersionZon(allocator);

    // Create dist directory
    try fs.cwd().makePath("dist");

    // Compress the binary
    try compressBinary(allocator);

    // Read the zip file and calculate hash
    const zip_path = "dist/rb-x86_64-pc-windows-msvc.zip";
    const zip_data = try fs.cwd().readFileAlloc(allocator, zip_path, 100 * 1024 * 1024);
    defer allocator.free(zip_data);

    // Calculate SHA-256 hash
    var hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(zip_data, &hash, .{});

    // Convert hash to hex string
    var hex_hash: [std.crypto.hash.sha2.Sha256.digest_length * 2]u8 = undefined;
    _ = std.fmt.bufPrint(&hex_hash, "{}", .{std.fmt.fmtSliceHexLower(&hash)}) catch unreachable;

    // Generate scoop manifest
    try generateScoopManifest(allocator, version, &hex_hash);

    std.debug.print("✅ Release preparation completed successfully\n", .{});
}

fn parseVersion(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    // Find .version = "x.x.x" pattern
    const version_start = std.mem.indexOf(u8, content, ".version = \"") orelse return error.VersionNotFound;
    const quote_start = version_start + 12;
    const quote_end = std.mem.indexOfPos(u8, content, quote_start, "\"") orelse return error.VersionNotFound;

    const version = content[quote_start..quote_end];
    return allocator.dupe(u8, version);
}

fn writeVersionZon(allocator: std.mem.Allocator, version: []const u8) !void {
    const version_content = try std.fmt.allocPrint(allocator, ".{{ .version = \"{s}\" }}\n", .{version});
    defer allocator.free(version_content);

    const file = try fs.cwd().createFile("src/version.zon", .{});
    defer file.close();
    try file.writeAll(version_content);
}

fn formatVersionZon(allocator: std.mem.Allocator) !void {
    const argv = [_][]const u8{ "zig", "fmt", "src/version.zon" };
    var child = std.process.Child.init(&argv, allocator);
    _ = try child.spawnAndWait();
}

fn compressBinary(allocator: std.mem.Allocator) !void {
    const argv = [_][]const u8{
        "powershell",
        "Compress-Archive",
        "-Path",
        "zig-out/bin/rb.exe",
        "-DestinationPath",
        "dist/rb-x86_64-pc-windows-msvc.zip",
        "-Force",
    };
    var child = std.process.Child.init(&argv, allocator);
    _ = try child.spawnAndWait();
}

fn generateScoopManifest(allocator: std.mem.Allocator, version: []const u8, hash: []const u8) !void {
    const url = try std.fmt.allocPrint(allocator, "https://github.com/ryuapp/rb/releases/download/v{s}/rb-x86_64-pc-windows-msvc.zip", .{version});
    defer allocator.free(url);

    const manifest = .{
        .version = version,
        .homepage = "https://github.com/ryuapp/rb",
        .license = "MIT",
        .architecture = .{
            .@"64bit" = .{
                .url = url,
                .hash = hash,
            },
        },
        .bin = "rb.exe",
        .checkver = "github",
        .autoupdate = .{
            .architecture = .{
                .@"64bit" = .{
                    .url = "https://github.com/ryuapp/rb/releases/download/v$version/rb-x86_64-pc-windows-msvc.zip",
                },
            },
        },
    };

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try json.stringify(manifest, .{ .whitespace = .indent_2 }, buffer.writer());
    try buffer.append('\n');

    const file = try fs.cwd().createFile("rb.json", .{});
    defer file.close();
    try file.writeAll(buffer.items);
}
