const std = @import("std");
const zigwin32 = @import("zigwin32");

const com = zigwin32.system.com;
const shell = zigwin32.ui.shell;
const foundation = zigwin32.foundation;
const debug = zigwin32.system.diagnostics.debug;
const kernel32 = zigwin32.kernel32;
const ole32 = zigwin32.ole32;
const shell32 = zigwin32.shell32;

const IShellItem = shell.IShellItem;
const IFileOperation = shell.IFileOperation;
const IID_IShellItem = shell.IID_IShellItem;
const IID_IFileOperation = shell.IID_IFileOperation;
const CLSID_FileOperation = shell.CLSID_FileOperation;
const CLSCTX_ALL = com.CLSCTX_ALL;
const COINIT_MULTITHREADED = com.COINIT_MULTITHREADED;

const CoUninitialize = ole32.CoUninitialize;
const CoInitializeEx = ole32.CoInitializeEx;
const CoCreateInstance = ole32.CoCreateInstance;
const SHCreateItemFromParsingName = shell32.SHCreateItemFromParsingName;

const FormatMessageW = kernel32.FormatMessageW;
const LocalFree = kernel32.LocalFree;

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
    if (hr.failed) return error.CoCreateInstanceFailed;
    return file_op;
}

fn getShellItem(filename: [:0]u16) !*IShellItem {
    var shell_item: *IShellItem = undefined;
    const result = SHCreateItemFromParsingName(filename, null, IID_IShellItem, @ptrCast(&shell_item));
    if (result.failed) return error.CreateItemFailed;
    return shell_item;
}

pub fn trash(io: std.Io, allocator: std.mem.Allocator, filename: []const u8) !i32 {
    // Initialize the COM Library
    // See: https://learn.microsoft.com/en-us/windows/win32/learnwin32/initializing-the-com-library
    const hr_init = CoInitializeEx(null, COINIT_MULTITHREADED);
    defer CoUninitialize();
    if (hr_init.failed) return error.CoInitializeFailed;

    var file_op = getFileOperation() catch |err| {
        return err;
    };
    const operation_flags = FOF_SILENT | FOF_NOERRORUI | FOF_NOCONFIRMATION | FOFX_ADDUNDORECORD | FOFX_EARLYFAILURE | FOFX_RECYCLEONDELETE;
    const set_flags_result = file_op.SetOperationFlags(operation_flags);
    if (set_flags_result.failed) return @bitCast(set_flags_result);
    const realpath = std.Io.Dir.cwd().realPathFileAlloc(io, filename, allocator) catch |err| {
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
    const delete_result = file_op.DeleteItem(shell_item, null);
    if (delete_result.failed) return @bitCast(delete_result);

    const perform_result = file_op.PerformOperations();
    var operations_aborted: i32 = 0;
    const aborted_result = file_op.GetAnyOperationsAborted(&operations_aborted);

    if (perform_result.failed) {
        return switch (perform_result) {
            foundation.E_ACCESSDENIED,
            shell.COPYENGINE_E_ACCESS_DENIED_DEST,
            shell.COPYENGINE_E_ACCESS_DENIED_SRC,
            shell.COPYENGINE_E_ACCESSDENIED_READONLY,
            => 5,
            shell.COPYENGINE_E_SHARING_VIOLATION_DEST,
            shell.COPYENGINE_E_SHARING_VIOLATION_SRC,
            => 32,
            shell.COPYENGINE_E_DISK_FULL,
            shell.COPYENGINE_E_DISK_FULL_CLEAN,
            shell.COPYENGINE_E_REMOVABLE_FULL,
            => 112,
            shell.COPYENGINE_E_DIR_NOT_EMPTY => 145,
            shell.COPYENGINE_E_NEWFILE_NAME_TOO_LONG,
            shell.COPYENGINE_E_NEWFOLDER_NAME_TOO_LONG,
            shell.COPYENGINE_E_PATH_TOO_DEEP_DEST,
            shell.COPYENGINE_E_PATH_TOO_DEEP_SRC,
            shell.COPYENGINE_E_RECYCLE_PATH_TOO_LONG,
            => 206,
            shell.COPYENGINE_E_FILE_TOO_LARGE,
            shell.COPYENGINE_E_RECYCLE_SIZE_TOO_BIG,
            => 223,
            shell.COPYENGINE_E_REQUIRES_ELEVATION => 740,
            shell.COPYENGINE_E_CANCELLED,
            shell.COPYENGINE_E_USER_CANCELLED,
            => 1223,
            else => @bitCast(perform_result),
        };
    }
    if (aborted_result.failed) return @bitCast(aborted_result);
    if (operations_aborted != 0) return @intFromEnum(foundation.ERROR_CANCELLED);
    return 0;
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
