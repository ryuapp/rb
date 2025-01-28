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

/// Converts UTF-8 into UTF-16 LE
fn utf8ToUtf16LeDynamic(utf8: []const u8) !*const []u16 {
    const len = try std.unicode.calcUtf16LeLen(utf8);
    const alc = std.heap.page_allocator;
    var utf16_buffer = try alc.alloc(u16, len);

    _ = try std.unicode.utf8ToUtf16Le(utf16_buffer, utf8);

    return &utf16_buffer;
}

pub fn trash(filename: []const u8) !i32 {
    const file_op: LPSHFILEOPSTRUCT = .{
        .hwnd = null,
        .wFunc = FO_DELETE,
        .pFrom = (try utf8ToUtf16LeDynamic(filename)).ptr,
        .pTo = std.unicode.utf8ToUtf16LeStringLiteral("").ptr,
        .fFlags = FOF_ALLOWUNDO | FOF_SILENT | FOF_WANTNUKEWARNING,
        .fAnyOperationsAborted = @as(windows.BOOL, 0),
        .hNameMappings = null,
        .lpszProgressTitle = null,
    };

    return SHFileOperationW(file_op);
}
