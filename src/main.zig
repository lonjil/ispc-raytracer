const std = @import("std");

const daedelus = @import("platform.zig");

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;
    var daedelus_instance = daedelus.Instance.init(allocator, "ispc_raytracer") catch |err| {
        daedelus.fatalErrorMessage(allocator, "Couldn't create instance", "Fatal error");
        return;
    };
    defer daedelus_instance.deinit();

    const window = daedelus_instance.createWindow("ispc-raytracer", 1280, 720, null, null) catch {
        daedelus.fatalErrorMessage(allocator, "Couldn't create window", "Fatal error");
        return;
    };
    defer window.deinit();

    const window_dim = window.getSize();
    window.show(); // TODO: show loading screen of some kind?

    var bitmap = daedelus.Bitmap.create(allocator, window_dim.width, window_dim.height, .TopDown) catch unreachable;
    var row_iterator = bitmap.rowIterator();
    while (row_iterator.next()) |row| {
        for (row.pixels) |*pixel, i| {
            pixel.* = .{
                .comp = .{
                    .r = @truncate(u8, row.row),
                    .g = @truncate(u8, i),
                    .b = 255,
                    .a = 255,
                },
            };
        }
    }

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
