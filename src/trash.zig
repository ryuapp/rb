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

extern "shell32" fn SHFileOperationW(lp_file_op: LPSHFILEOPSTRUCT) callconv(windows.WINAPI) windows.BOOL;

const FO_DELETE: u32 = 3;
const FOF_ALLOWUNDO: u16 = 64;
const FOF_SILENT: u16 = 4;
const FOF_WANTNUKEWARNING: u16 = 16384;

fn utf8ToUtf16LeDynamic(utf8: []const u8) !*const []u16 {
    const len = try std.unicode.calcUtf16LeLen(utf8);
    var utf16_buffer = try std.heap.page_allocator.alloc(u16, len);

    _ = try std.unicode.utf8ToUtf16Le(utf16_buffer[0..len], utf8);

    return &utf16_buffer[0..len];
}

pub fn trash(filename: []const u8) !windows.BOOL {
    const filename_utf8 = try utf8ToUtf16LeDynamic(filename);
    const file_op: LPSHFILEOPSTRUCT = .{
        .hwnd = null,
        .wFunc = FO_DELETE,
        .pFrom = filename_utf8.ptr,
        .pTo = std.unicode.utf8ToUtf16LeStringLiteral("").ptr,
        .fFlags = FOF_ALLOWUNDO | FOF_SILENT | FOF_WANTNUKEWARNING,
        .fAnyOperationsAborted = @as(windows.BOOL, 0),
        .hNameMappings = null,
    };

    const result = SHFileOperationW(file_op);
    if (result != 0) {
        const prefix_msg = "gm: cannot remove";
        switch (result) {
            2 => try std.io.getStdErr().writer().print("{s} '{s}': Not found", .{ prefix_msg, filename }),
            5 => try std.io.getStdErr().writer().print("{s} '{s}': Access denied", .{ prefix_msg, filename }),
            32 => try std.io.getStdErr().writer().print("{s} '{s}': The process cannot access the file because it is being used by another process", .{ prefix_msg, filename }),
            else => try std.io.getStdErr().writer().print("{s} '{s}': Error code: {d}", .{ prefix_msg, filename, result }),
        }
    }

    return result;
}
