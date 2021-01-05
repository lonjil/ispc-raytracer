const std = @import("std");
const Builder = std.build.Builder;
const path = std.fs.path;
const builtin = @import("builtin");

fn addIspcObject(b: *Builder, exe: anytype, in_file: []const u8, target: ?[]const u8, is_release: bool) !void {
    // TODO: dependency management. Automatically pick target TODO:
    // get cpuid to tell us what target to use instead of just picking
    // our lowest common denominator of SSE2
    const target_param = try std.mem.concat(b.allocator, u8, &[_][]const u8{
        "--target=",
        target orelse "sse2-i32x4",
    });
    const out_file_obj_name = try std.mem.concat(b.allocator, u8, &[_][]const u8{ std.fs.path.basename(in_file), ".obj" });
    const out_file = try std.fs.path.join(b.allocator, &[_][]const u8{
        b.build_root,
        b.cache_root,
        out_file_obj_name,
    });
    const run_cmd = b.addSystemCommand(&[_][]const u8{
        "ispc",
        in_file,
        "-o",
        out_file,
        "--addressing=64",
        target_param,
        if (is_release) "-O3" else "-O0",
    });
    exe.step.dependOn(&run_cmd.step);
    exe.addObjectFile(out_file);
}

pub fn build(b: *Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();



    const exe = b.addExecutable("ispc-raytracer", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    try addIspcObject(b, exe, "src/raytrace.ispc", null, b.is_release);
    const target2 =
        if (target.os_tag) |tag|
            tag
        else
            builtin.os.tag;
    if (target2 == .windows) {
        exe.subsystem = .Windows;
    } else {
        exe.linkSystemLibrary("c");
        exe.linkSystemLibrary("SDL2");
    }
    exe.install();


    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
