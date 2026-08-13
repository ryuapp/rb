const std = @import("std");
const builtin = @import("builtin");
const zigwin32 = @import("zigwin32");

const console = zigwin32.system.console;
const k32 = zigwin32.kernel32;

const is_windows = builtin.os.tag == .windows;

pub const Output = struct {
    pub fn init() !void {
        if (comptime is_windows) {
            try WindowsOutput.init();
        }
    }
    pub fn restore() void {
        if (comptime is_windows) {
            WindowsOutput.restore();
        }
    }
};
const WindowsOutput = struct {
    var console_output_cp: c_uint = @as(u32, 0);

    // Make a console output code is the same as before execution
    fn setAbortSignalHandler(comptime handler: *const fn () void) !void {
        const handler_routine = struct {
            fn handler_routine(dwCtrlType: u32) callconv(.winapi) i32 {
                if (dwCtrlType == console.CTRL_C_EVENT) {
                    handler();
                    return 1;
                } else {
                    return 0;
                }
            }
        }.handler_routine;

        if (k32.SetConsoleCtrlHandler(handler_routine, 1) == 0) {
            return error.SetConsoleCtrlHandlerFailed;
        }
    }
    fn abortSignalHandler() void {
        restore();
        std.process.exit(0);
    }

    pub fn init() !void {
        // Set a console output code page to UTF-8
        const CP_UTF8 = 65001;
        console_output_cp = k32.GetConsoleOutputCP();
        try setAbortSignalHandler(abortSignalHandler);
        _ = k32.SetConsoleOutputCP(CP_UTF8);
    }
    pub fn restore() void {
        if (console_output_cp != 0)
            _ = k32.SetConsoleOutputCP(console_output_cp);
    }
};
