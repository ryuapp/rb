const std = @import("std");
const windows = std.os.windows;

const LPSHFILEOPSTRUCT = extern struct {
    hwnd: ?*windows.HWND,
    wFunc: u32,
    pFrom: ?[*]const u16, // PCWSTR
    pTo: ?[*]const u16, // PCWSTR
    fFlags: u16,
    fAnyOperationsAborted: windows.BOOL,
    hNameMappings: ?*windows.LPVOID,
    lpszProgressTitle: ?[*:0]const u16,
};

extern "shell32" fn SHFileOperationW(lpFileOp: LPSHFILEOPSTRUCT) callconv(windows.WINAPI) i32;

const FO_DELETE: u32 = 3;
const FOF_ALLOWUNDO: u16 = 64;
const FOF_SILENT: u16 = 4;
const FOF_WANTNUKEWARNING: u16 = 16384;

pub fn trash(allocator: std.mem.Allocator, filename: []const u8) !i32 {
    // Convert filename to UTF-16
    const filename_len = try std.unicode.calcUtf16LeLen(filename);
    const utf16_buffer = try allocator.alloc(u16, filename_len);
    defer allocator.free(utf16_buffer);
    _ = try std.unicode.utf8ToUtf16Le(utf16_buffer, filename);

    const file_op: LPSHFILEOPSTRUCT = .{
        .hwnd = null,
        .wFunc = FO_DELETE,
        .pFrom = utf16_buffer.ptr,
        .pTo = std.unicode.utf8ToUtf16LeStringLiteral("").ptr,
        .fFlags = FOF_ALLOWUNDO | FOF_SILENT | FOF_WANTNUKEWARNING,
        .fAnyOperationsAborted = @as(windows.BOOL, 0),
        .hNameMappings = null,
        .lpszProgressTitle = null,
    };

    return SHFileOperationW(file_op);
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
