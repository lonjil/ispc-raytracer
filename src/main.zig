const std = @import("std");

const daedelus = @import("platform.zig");

extern fn raytrace_ispc(u32, u32, [*]daedelus.Pixel) void;

fn renderToBitmap(bitmap: daedelus.Bitmap) !void {
    raytrace_ispc(bitmap.width, bitmap.height, bitmap.pixels.ptr);
}

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;
    var daedelus_instance = daedelus.Instance.init(allocator, "ispc_raytracer") catch |err| {
        daedelus.fatalErrorMessage(allocator, "Couldn't create instance", "Fatal error");
        return;
    };
    defer daedelus_instance.deinit();

    const window = daedelus_instance.createWindow(
        "ispc-raytracer",
        1280,
        720,
        null,
        null,
        .{ .resizable = false },
    ) catch {
        daedelus.fatalErrorMessage(allocator, "Couldn't create window", "Fatal error");
        return;
    };
    defer window.close();

    const window_dim = window.getSize();
    window.show(); // TODO: show loading screen of some kind?

    var bitmap = daedelus.Bitmap.create(allocator, window_dim.width, window_dim.height, .TopDown) catch unreachable;
    renderToBitmap(bitmap) catch {
        daedelus.fatalErrorMessage(allocator, "rendering failed", "rendering error");
    };

    defer bitmap.release(allocator);

    var running = true;

    while (running) {
        switch (window.getEvent()) {
            .CloseRequest => |_| {
                running = false;
            },
            .RedrawRequest => |redraw_request| {
                window.blit(bitmap, 0, 0) catch {
                    unreachable;
                };
            },
            .WindowResize => {
                daedelus.fatalErrorMessage(allocator, "How did this resize?", "Fatal error");
                return;
            },
        }
    }
}

pub const log = daedelus.log;
