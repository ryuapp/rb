const std = @import("std");
const process = std.process;
const json = std.json;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const cwd = std.Io.Dir.cwd();

    // Read build.zig.zon
    const build_zon_content = try cwd.readFileAlloc(io, "build.zig.zon", allocator, .limited(1024 * 1024));
    defer allocator.free(build_zon_content);

    // Parse version from build.zig.zon
    const version = try parseVersion(allocator, build_zon_content);
    defer allocator.free(version);

    // Write version.zon
    try writeVersionZon(io, allocator, version);

    // Format version.zon
    try formatVersionZon(io);

    // Create dist directory
    try cwd.createDirPath(io, "dist");

    // Build and compress for x86_64
    std.debug.print("Building x86_64-windows-msvc...\n", .{});
    const x64_prefix = "zig-out/release/x86_64-windows-msvc";
    try buildProject(io, allocator, "x86_64-windows-msvc", x64_prefix);
    try compressBinary(io, allocator, x64_prefix, "x86_64-pc-windows-msvc");
    const x64_hash = try calculateHash(io, allocator, "dist/rb-x86_64-pc-windows-msvc.zip");

    // Build and compress for aarch64
    std.debug.print("Building aarch64-windows-msvc...\n", .{});
    const arm64_prefix = "zig-out/release/aarch64-windows-msvc";
    try buildProject(io, allocator, "aarch64-windows-msvc", arm64_prefix);
    try compressBinary(io, allocator, arm64_prefix, "aarch64-pc-windows-msvc");
    const arm64_hash = try calculateHash(io, allocator, "dist/rb-aarch64-pc-windows-msvc.zip");

    // Generate scoop manifest
    try generateScoopManifest(io, allocator, version, x64_hash, arm64_hash);

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

fn writeVersionZon(io: std.Io, allocator: std.mem.Allocator, version: []const u8) !void {
    const version_content = try std.fmt.allocPrint(allocator, ".{{ .version = \"{s}\" }}\n", .{version});
    defer allocator.free(version_content);

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = "src/version.zon",
        .data = version_content,
    });
}

fn formatVersionZon(io: std.Io) !void {
    const argv = [_][]const u8{ "zig", "fmt", "src/version.zon" };
    try runCommand(io, &argv);
}

fn buildProject(io: std.Io, allocator: std.mem.Allocator, target: []const u8, prefix: []const u8) !void {
    const target_arg = try std.fmt.allocPrint(allocator, "-Dtarget={s}", .{target});
    defer allocator.free(target_arg);

    const argv = [_][]const u8{
        "zig",
        "build",
        target_arg,
        "-Doptimize=ReleaseSmall",
        "--prefix",
        prefix,
    };
    try runCommand(io, &argv);
}

fn compressBinary(io: std.Io, allocator: std.mem.Allocator, prefix: []const u8, target: []const u8) !void {
    const dest_path = try std.fmt.allocPrint(allocator, "dist/rb-{s}.zip", .{target});
    defer allocator.free(dest_path);
    const binary_path = try std.fmt.allocPrint(allocator, "{s}/bin/rb.exe", .{prefix});
    defer allocator.free(binary_path);

    const argv = [_][]const u8{
        "powershell",
        "Compress-Archive",
        "-Path",
        binary_path,
        "-DestinationPath",
        dest_path,
        "-Force",
    };
    try runCommand(io, &argv);
}

fn runCommand(io: std.Io, argv: []const []const u8) !void {
    var child = try process.spawn(io, .{ .argv = argv });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.ChildProcessFailed,
        else => return error.ChildProcessFailed,
    }
}

fn calculateHash(io: std.Io, allocator: std.mem.Allocator, zip_path: []const u8) ![std.crypto.hash.sha2.Sha256.digest_length * 2]u8 {
    const zip_data = try std.Io.Dir.cwd().readFileAlloc(io, zip_path, allocator, .limited(100 * 1024 * 1024));
    defer allocator.free(zip_data);

    // Calculate SHA-256 hash
    var hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(zip_data, &hash, .{});

    // Convert hash to hex string
    return std.fmt.bytesToHex(hash, .lower);
}

fn generateScoopManifest(io: std.Io, allocator: std.mem.Allocator, version: []const u8, x64_hash: [std.crypto.hash.sha2.Sha256.digest_length * 2]u8, arm64_hash: [std.crypto.hash.sha2.Sha256.digest_length * 2]u8) !void {
    const x64_url = try std.fmt.allocPrint(allocator, "https://github.com/ryuapp/rb/releases/download/v{s}/rb-x86_64-pc-windows-msvc.zip", .{version});
    defer allocator.free(x64_url);

    const arm64_url = try std.fmt.allocPrint(allocator, "https://github.com/ryuapp/rb/releases/download/v{s}/rb-aarch64-pc-windows-msvc.zip", .{version});
    defer allocator.free(arm64_url);

    const manifest = .{
        .version = version,
        .homepage = "https://github.com/ryuapp/rb",
        .license = "MIT-0",
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

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = "rb.json",
        .data = manifest_str,
    });
}
