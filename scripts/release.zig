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

    // Build and compress for x86_64
    std.debug.print("Building x86_64-windows-msvc...\n", .{});
    try buildProject(allocator, "x86_64-windows-msvc");
    try compressBinary(allocator, "x86_64-pc-windows-msvc");
    const x64_hash = try calculateHash(allocator, "dist/rb-x86_64-pc-windows-msvc.zip");

    // Build and compress for aarch64
    std.debug.print("Building aarch64-windows-msvc...\n", .{});
    try buildProject(allocator, "aarch64-windows-msvc");
    try compressBinary(allocator, "aarch64-pc-windows-msvc");
    const arm64_hash = try calculateHash(allocator, "dist/rb-aarch64-pc-windows-msvc.zip");

    // Generate scoop manifest
    try generateScoopManifest(allocator, version, x64_hash, arm64_hash);

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

fn buildProject(allocator: std.mem.Allocator, target: []const u8) !void {
    const target_arg = try std.fmt.allocPrint(allocator, "-Dtarget={s}", .{target});
    defer allocator.free(target_arg);

    const argv = [_][]const u8{
        "zig",
        "build",
        target_arg,
        "-Doptimize=ReleaseSmall",
    };
    var child = std.process.Child.init(&argv, allocator);
    _ = try child.spawnAndWait();
}

fn compressBinary(allocator: std.mem.Allocator, target: []const u8) !void {
    const dest_path = try std.fmt.allocPrint(allocator, "dist/rb-{s}.zip", .{target});
    defer allocator.free(dest_path);

    const argv = [_][]const u8{
        "powershell",
        "Compress-Archive",
        "-Path",
        "zig-out/bin/rb.exe",
        "-DestinationPath",
        dest_path,
        "-Force",
    };
    var child = std.process.Child.init(&argv, allocator);
    _ = try child.spawnAndWait();
}

fn calculateHash(allocator: std.mem.Allocator, zip_path: []const u8) ![std.crypto.hash.sha2.Sha256.digest_length * 2]u8 {
    const zip_data = try fs.cwd().readFileAlloc(allocator, zip_path, 100 * 1024 * 1024);
    defer allocator.free(zip_data);

    // Calculate SHA-256 hash
    var hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(zip_data, &hash, .{});

    // Convert hash to hex string
    return std.fmt.bytesToHex(hash, .lower);
}

fn generateScoopManifest(allocator: std.mem.Allocator, version: []const u8, x64_hash: [std.crypto.hash.sha2.Sha256.digest_length * 2]u8, arm64_hash: [std.crypto.hash.sha2.Sha256.digest_length * 2]u8) !void {
    const x64_url = try std.fmt.allocPrint(allocator, "https://github.com/ryuapp/rb/releases/download/v{s}/rb-x86_64-pc-windows-msvc.zip", .{version});
    defer allocator.free(x64_url);

    const arm64_url = try std.fmt.allocPrint(allocator, "https://github.com/ryuapp/rb/releases/download/v{s}/rb-aarch64-pc-windows-msvc.zip", .{version});
    defer allocator.free(arm64_url);

    const manifest = .{
        .version = version,
        .homepage = "https://github.com/ryuapp/rb",
        .license = "MIT",
        .architecture = .{
            .@"64bit" = .{
                .url = x64_url,
                .hash = &x64_hash,
            },
            .arm64 = .{
                .url = arm64_url,
                .hash = &arm64_hash,
            },
        },
        .bin = "rb.exe",
        .checkver = "github",
        .autoupdate = .{
            .architecture = .{
                .@"64bit" = .{
                    .url = "https://github.com/ryuapp/rb/releases/download/v$version/rb-x86_64-pc-windows-msvc.zip",
                },
                .arm64 = .{
                    .url = "https://github.com/ryuapp/rb/releases/download/v$version/rb-aarch64-pc-windows-msvc.zip",
                },
            },
        },
    };

    const manifest_str = try std.fmt.allocPrint(allocator, "{f}\n", .{json.fmt(manifest, .{ .whitespace = .indent_2 })});
    defer allocator.free(manifest_str);

    const file = try fs.cwd().createFile("rb.json", .{});
    defer file.close();
    try file.writeAll(manifest_str);
}
