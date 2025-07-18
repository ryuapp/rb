const std = @import("std");
const zigwin32 = @import("zigwin32");

const com = zigwin32.system.com;
const shell = zigwin32.ui.shell;
const foundation = zigwin32.foundation;
const debug = zigwin32.system.diagnostics.debug;
const memory = zigwin32.system.memory;

const IShellItem = shell.IShellItem;
const IFileOperation = shell.IFileOperation;
const IID_IShellItem = shell.IID_IShellItem;
const IID_IFileOperation = shell.IID_IFileOperation;
const CLSID_FileOperation = shell.CLSID_FileOperation;
const CLSCTX_ALL = com.CLSCTX_ALL;
const COINIT_MULTITHREADED = com.COINIT_MULTITHREADED;

const CoUninitialize = com.CoUninitialize;
const CoInitializeEx = com.CoInitializeEx;
const CoCreateInstance = com.CoCreateInstance;
const SHCreateItemFromParsingName = shell.SHCreateItemFromParsingName;

const FormatMessageW = debug.FormatMessageW;
const LocalFree = memory.LocalFree;

// Operation Flags
// See: https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ifileoperation-setoperationflags
const FOF_SILENT = shell.FOF_SILENT;
const FOF_NOERRORUI = shell.FOF_NOERRORUI;
const FOF_NOCONFIRMATION = shell.FOF_NOCONFIRMATION;
const FOFX_ADDUNDORECORD = shell.FOFX_ADDUNDORECORD;
const FOFX_EARLYFAILURE = shell.FOFX_EARLYFAILURE;
const FOFX_RECYCLEONDELETE = shell.FOFX_RECYCLEONDELETE;

fn getFileOperation() !*IFileOperation {
    var file_op: *IFileOperation = undefined;
    const hr = CoCreateInstance(
        CLSID_FileOperation,
        null,
        CLSCTX_ALL,
        IID_IFileOperation,
        @ptrCast(&file_op),
    );
    if (hr != 0) return error.CoCreateInstanceFailed;
    return file_op;
}

fn getShellItem(filename: [:0]u16) !*IShellItem {
    var shell_item: *IShellItem = undefined;
    const result = SHCreateItemFromParsingName(filename, null, IID_IShellItem, @ptrCast(&shell_item));
    if (result != 0) return error.CreateItemFailed;
    return shell_item;
}

pub fn trash(allocator: std.mem.Allocator, filename: []const u8) !i32 {
    // Initialize the COM Library
    // See: https://learn.microsoft.com/en-us/windows/win32/learnwin32/initializing-the-com-library
    const hr_init = CoInitializeEx(null, COINIT_MULTITHREADED);
    defer CoUninitialize();
    if (hr_init != 0) return error.CoInitializeFailed;

    var file_op = getFileOperation() catch |err| {
        return err;
    };
    const operation_flags = FOF_SILENT | FOF_NOERRORUI | FOF_NOCONFIRMATION | FOFX_ADDUNDORECORD | FOFX_EARLYFAILURE | FOFX_RECYCLEONDELETE;
    _ = file_op.SetOperationFlags(operation_flags);
    const realpath = std.fs.cwd().realpathAlloc(allocator, filename) catch |err| {
        if (err == error.FileNotFound) {
            return 2;
        }
        return err;
    };
    defer allocator.free(realpath);
    // Convert UTF-8 to UTF-16
    const filepath = try std.unicode.utf8ToUtf16LeAllocZ(allocator, realpath);
    defer allocator.free(filepath);

    const shell_item = getShellItem(filepath) catch |err| {
        return err;
    };
    _ = file_op.DeleteItem(shell_item, null);

    const result = file_op.PerformOperations();
    return switch (result) {
        zigwin32.foundation.E_ACCESSDENIED => 5,
        shell.COPYENGINE_E_SHARING_VIOLATION_SRC => 32,
        else => result,
    };
}

pub fn getErrorMessage(allocator: std.mem.Allocator, error_code: i32) ![]u8 {
    var message_buffer: ?[*:0]u16 = null;
    const flags = debug.FORMAT_MESSAGE_OPTIONS{
        .FROM_SYSTEM = 1,
        .IGNORE_INSERTS = 1,
        .ALLOCATE_BUFFER = 1,
    };

    const chars_written = FormatMessageW(
        flags,
        null,
        @intCast(error_code),
        0,
        @ptrCast(&message_buffer),
        0,
        null,
    );

    if (chars_written == 0 or message_buffer == null) {
        return std.fmt.allocPrint(allocator, "Error Code: {d}", .{error_code});
    }

    defer _ = LocalFree(@intCast(@intFromPtr(message_buffer)));

    const message_utf16 = message_buffer.?[0..chars_written];
    var utf8_message = try std.unicode.utf16LeToUtf8Alloc(allocator, message_utf16);

    // Remove trailing newline/carriage return if present
    if (utf8_message.len > 0) {
        var end = utf8_message.len;
        while (end > 0 and (utf8_message[end - 1] == '\n' or utf8_message[end - 1] == '\r')) {
            end -= 1;
        }
        utf8_message = utf8_message[0..end];
    }

    return utf8_message;
}
