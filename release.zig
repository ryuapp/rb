const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

// FIXME: Use build.zig.zon to get version
const version = "0.1.0";

// FIXME: Cannot get hash as string
fn getHash(comptime filename: []const u8) ![]const u8 {
    const file = @embedFile(filename);
    var sha256 = Sha256.init(.{});
    sha256.update(file);
    const bytes = sha256.finalResult();
    const hex = std.fmt.bytesToHex(bytes, .lower);
    var hash: [64]u8 = undefined;
    var i: usize = 0;
    for (hex) |c| {
        hash[i] = c;
        i += 1;
    }
    // DEBUG
    std.debug.print("hash: {s}\n", .{hash});
    return &hash;
}
fn toReplaced(allocator: std.mem.Allocator, input: []const u8, placeholder: []const u8, replacement: []const u8) ![]const u8 {
    const size = std.mem.replacementSize(u8, input, placeholder, replacement);
    const output = try allocator.alloc(u8, size);
    _ = std.mem.replace(u8, input, placeholder, replacement, output);
    return output;
}

pub fn main() !void {
    const alc = std.heap.page_allocator;
    const scoop_json = try std.fs.cwd().createFile("ra.json", .{
        .read = true,
        .truncate = true,
    });
    defer scoop_json.close();
    const scoop_template = .{
        .version = "PLACEHOLDER_VERSION",
        .homepage = "https://github.com/ryuapp/rb",
        .license = "MIT",
        .architecture = .{
            .PLACEHOLDER_64BIT = .{
                .url = "https://github.com/ryuapp/rb/releases/download/vPLACEHOLDER_VERSION/rb-x86_64-pc-windows-msvc.zip",
                .hash = try getHash("dist/rb-x86_64-pc-windows-msvc.zip"),
            },
        },
        .bin = "rb.exe",
        .checkver = "github",
        .autoupdate = .{
            .architecture = .{
                .PLACEHOLDER_64BIT = .{
                    .url = "https://github.com/ryuapp/rb/releases/download/v$version/rb-x86_64-pc-windows-msvc.zip",
                },
            },
        },
    };
    var buf: [10240]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var string = std.ArrayList(u8).init(fba.allocator());
    try std.json.stringify(
        scoop_template,
        .{ .whitespace = .indent_2 },
        string.writer(),
    );
    var output = try toReplaced(alc, string.items, "PLACEHOLDER_VERSION", version);
    output = try toReplaced(alc, output, "PLACEHOLDER_64BIT", "64bit");
    try scoop_json.writeAll(output);
    _ = try scoop_json.write("\n");
}
