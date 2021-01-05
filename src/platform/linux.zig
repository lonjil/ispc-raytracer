const std = @import("std");
const Allocator = std.mem.Allocator;
const sdl = @cImport(@cInclude("SDL2/SDL.h"));


pub const Pixel = extern union {
    bits: u32,
    array: [4]u8,
    comp: struct {
        b: u8,
        g: u8,
        r: u8,
        a: u8,
    },
};

pub const Bitmap = struct {
    pixels: []Pixel,
    width: u32,
    height: u32,
    stride: u32,
    direction: Direction,
    const Direction = enum { TopDown, BottomUp };
    pub fn create(allocator: *Allocator, width: u32, height: u32, direction: Direction) !@This() {
        const pixels = try allocator.alloc(Pixel, width * height);
        return @This(){ .pixels = pixels, .width = width, .height = height, .stride = width, .direction = direction };
    }

    const Row = struct { row: u32, pixels: []Pixel };

    const RowIterator = struct {
        current: u32 = 0,
        pixels: []Pixel,
        height: u32,
        stride: u32,
        width: u32,
        pub fn next(self: *@This()) ?Row {
            if (self.current == self.height) {
                return null;
            } else {
                const row = .{
                    .row = self.current,
                    .pixels = self.pixels[self.current * self.stride .. self.current * (self.stride) + self.width],
                };
                self.current += 1;
                return row;
            }
        }
    };

    pub fn rowIterator(self: *@This()) RowIterator {
        return .{
            .pixels = self.pixels,
            .height = self.height,
            .stride = self.stride,
            .width = self.width,
        };
    }

    pub fn release(self: *@This(), allocator: *Allocator) void {
        allocator.free(self.pixels);
        self.* = undefined;
    }
};

extern fn SDL_GetErrorMsg(buffer: [*c]u8, len: c_int) [*c]u8;

fn getSdlError() [*c]u8 {
    const @"im a static :)" = struct {
        threadlocal var buffer: [1024]u8 = undefined;
    };
    _ = SDL_GetErrorMsg(&@"im a static :)".buffer,1024);
    return &@"im a static :)".buffer;
}

pub const Instance = struct {
    instance_name: []u8,
    allocator: *std.mem.Allocator,
    thread: std.Thread.Id,
    windows: std.ArrayList(*Window),
    w_lock: std.Mutex = .{},
    pub fn init(allocator: *std.mem.Allocator, their_instance_name: []const u8) !@This() {
        const instance_name = try allocator.dupe(u8, their_instance_name);
        errdefer allocator.free(instance_name);
        sdl.SDL_SetMainReady();
        if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
            std.log.err("SDL Init error: {}\n", .{getSdlError()});
            return error.InitError;
        }

        return @This(){
                .instance_name = instance_name,
                .allocator = allocator,
                .thread = std.Thread.getCurrentId(),
                .windows = std.ArrayList(*Window).init(allocator),
            };
    }
    pub fn pump(self: *@This()) void {
        // todo: whenever the event queue is empty, move SDL events to it.
        if (std.Thread.getCurrentId() != self.thread)
            @panic("Gotta pump in the video thread newb.");
        sdl.SDL_PumpEvents();
        var evs: [10]sdl.SDL_Event = undefined;
        while (true) {
            const stored = sdl.SDL_PeepEvents(&evs, 10, .SDL_GETEVENT, sdl.SDL_FIRSTEVENT, sdl.SDL_LASTEVENT);
            if (stored < 0) {
                std.log.err("Event peep error {}: {}", .{stored, getSdlError()});
                return;
            } else if (stored == 0) {
                return;
            } else {
                for (evs) |ev| {
                    switch (ev.type) {
                        sdl.SDL_WINDOWEVENT => std.log.info("hi {}\n", .{ev.window}),
                        else => {},
                    }
                }
            }
        }
    }

    pub fn createWindow(self: *@This(), title: []const u8, width: i32, height: i32, x: ?i32, y: ?i32) !*Window {
        const allocator = self.allocator;
        var win = try allocator.create(Window);
        errdefer allocator.destroy(win);
        win.title = try std.cstr.addNullByte(allocator, title);
        errdefer allocator.destroy(win.title);
        if (sdl.SDL_CreateWindow(win.title,
            x orelse sdl.SDL_WINDOWPOS_UNDEFINED,
            y orelse sdl.SDL_WINDOWPOS_UNDEFINED,
            width,
            height,
            sdl.SDL_WINDOW_OPENGL,
        )) |sdlwin| {
            win.win = sdlwin;
        } else {
            std.log.err("SDL window creation error: {}\n", .{getSdlError()});
            return error.CouldNotCreateWindow;
        }
        var w: c_int = undefined;
        var h: c_int = undefined;
        sdl.SDL_GetWindowSize(win.win, &w, &h);
        win._size.height = @intCast(u32,h);
        win._size.width = @intCast(u32,w);
        win.event_queue = std.atomic.Queue(Window.Event).init();
        win.id = sdl.SDL_GetWindowID(win.win);
        if (win.id == 0) {
            std.log.err("SDL window creation error: {}\n", .{getSdlError()});
            return error.CouldNotCreateWindow;
        }
        var held = self.w_lock.acquire();
        try self.windows.append(win);
        held.release();
        return win;
    }

    pub fn deinit(self: *@This()) void {
        sdl.SDL_Quit();
        self.allocator.free(self.instance_name);
    }
};

const Window = struct {
    allocator: *Allocator,
    _size: _Size,
    win: *sdl.SDL_Window,
    id: u32,
    title: [*c]u8,

    // TODO: Verify the atomics in here. I'm pretty sure I'm right but I'm not 100%
    event_queue: EventQueue,
    waiter_queue: ?*Node = null,

    const Dim = struct { width: u32, height: u32 };

    const _Size = struct {
        mutex: std.Mutex = .{},
        width: u32,
        height: u32,
        fn get(self: *@This()) Dim {
            const lock = self.mutex.acquire();
            defer lock.release();
            return .{ .width = self.width, .height = self.height };
        }
        fn set(self: *@This(), width: u32, height: u32) void {
            const lock = self.mutex.acquire();
            defer lock.release();
            self.width = width;
            self.height = height;
        }
    };

    const Node = struct {
        reset_event: std.StaticResetEvent = .{},
        next: ?*Node,
    };

    const EventQueue = std.atomic.Queue(Event);
    pub fn deinit(self: *@This()) void {
        _ = sdl.SDL_DestroyWindow(self.win);
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    const Event = union(enum) {
        CloseRequest: void, RedrawRequest: struct { x: i32, y: i32, width: u32, height: u32 }, WindowResize: struct {
            width: u32,
            height: u32,
            old_width: u32,
            old_height: u32,
        }
    };

    

    fn addEvent(self: *@This(), event: Event) !void {
        const node = try self.allocator.create(Window.EventQueue.Node);
        node.* = .{ .data = event };
        self.event_queue.put(node);
        while (@atomicLoad(?*Node, &self.waiter_queue, .Monotonic)) |waiter_node| {
            if (@cmpxchgWeak(?*Node, &self.waiter_queue, waiter_node, waiter_node.next, .Monotonic, .Monotonic)) |_| {} else {
                waiter_node.reset_event.set();
                return;
            }
        }
    }

    pub fn getSize(self: *@This()) Dim {
        return self._size.get();
    }

    pub fn getEvent(self: *@This()) Event {
        if (self.pollEvent()) |event| {
            return event;
        } else {
            while (true) {
                var node = Node{ .next = @atomicLoad(?*Node, &self.waiter_queue, .Monotonic) };
                if (self.pollEvent()) |event| {
                    return event;
                } else {
                    if (@cmpxchgWeak(?*Node, &self.waiter_queue, node.next, &node, .Monotonic, .Monotonic)) |_| {} else {
                        node.reset_event.wait();
                    }
                }
            }
        }
    }

    pub fn pollEvent(self: *@This()) ?Event {
        if (self.event_queue.get()) |event| {
            defer self.allocator.destroy(event);
            _ = self.event_queue.remove(event);
            return event.data;
        } else {
            return null;
        }
    }

    pub fn show(self: *@This()) void {
        // show window
    }
    pub fn hide(self: *@This()) void {
        // hide window
    }
    pub fn blit(
        self: *@This(),
        bitmap: Bitmap,
        dest_x: u32,
        dest_y: u32,
    ) error{BlitError}!void {
        
    }
};

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = switch (message_level) {
        .emerg => "emergency",
        .alert => "alert",
        .crit => "critical",
        .err => "error",
        .warn => "warning",
        .notice => "notice",
        .info => "info",
        .debug => "debug",
    };
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const held = std.debug.getStderrMutex().acquire();
    defer held.release();
    var writer = std.io.getStdErr().writer();

    _ = writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch {};
}

pub fn fatalErrorMessage(allocator: *Allocator, error_str: []const u8, title: []const u8) void {
    // do stuff
}
