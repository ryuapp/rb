const std = @import("std");
const windows = @import("std").os.windows;

const LPSHFILEOPSTRUCT = extern struct {
    hwnd: ?*windows.HWND,
    wFunc: u32,
    pFrom: [*]u16, // PCWSTR
    pTo: windows.PCWSTR,
    fFlags: u16,
    fAnyOperationsAborted: windows.BOOL,
    hNameMappings: ?*windows.LPVOID,
};

extern "shell32" fn SHFileOperationW(lpfileop: LPSHFILEOPSTRUCT) callconv(windows.WINAPI) windows.BOOL;

const FO_DELETE: u32 = 3;
const FOF_ALLOWUNDO: u16 = 64;
const FOF_SILENT: u16 = 4;
const FOF_WANTNUKEWARNING: u16 = 16384;

fn utf8ToUtf16LeDynamic(utf8: []const u8) !*const []u16 {
    const len = try std.unicode.calcUtf16LeLen(utf8);
    var utf16leBuffer = try std.heap.page_allocator.alloc(u16, len);

    _ = try std.unicode.utf8ToUtf16Le(utf16leBuffer[0..len], utf8);

    return &utf16leBuffer[0..len];
}

pub fn trash(filename: []const u8) !void {
    const utf16leFilename = try utf8ToUtf16LeDynamic(filename);
    const fileop: LPSHFILEOPSTRUCT = .{
        .hwnd = null,
        .wFunc = FO_DELETE,
        .pFrom = utf16leFilename.ptr,
        .pTo = std.unicode.utf8ToUtf16LeStringLiteral("").ptr,
        .fFlags = FOF_ALLOWUNDO | FOF_SILENT | FOF_WANTNUKEWARNING,
        .fAnyOperationsAborted = @as(windows.BOOL, 0),
        .hNameMappings = null,
    };

    const result = SHFileOperationW(fileop);
    switch (result) {
        0 => std.debug.print("Crumple up '{s}'!", .{filename}),
        2 => std.debug.print("'{s}' is not found.", .{filename}),
        5 => std.debug.print("Access denied to '{s}'.", .{filename}),
        32 => std.debug.print("'{s}' is being used by another process.", .{filename}),
        else => std.debug.print("gm: System error: {d}", .{result}),
    }
}
