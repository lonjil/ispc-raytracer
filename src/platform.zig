const builtin = @import("builtin");

//const windows = @import("platform/windows.zig");

pub usingnamespace @import(
    if (builtin.os.tag == .windows)
        "platform/windows.zig"
    else if (builtin.os.tag == .linux)
        "platform/linux.zig"
    else @compileError("Make a platform impl for this platform"));
