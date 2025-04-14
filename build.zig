const std = @import("std");

const bx = @import("build_bx.zig");
const bimg = @import("build_bimg.zig");
const bgfx = @import("build_bgfx.zig");
const sc = @import("build_shader_compiler.zig");
// const tp = @import("build_texture_packer.zig");

const CompileStep = std.Build.Step.Compile;
const Builder = std.Build.Builder;
const CrossTarget = std.zig.CrossTarget;
const Pkg = std.build.Pkg;

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    // EXE
    const exe = b.addExecutable(.{
        .name = "zig-bgfx-example",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const isWindows = target.result.os.tag == .windows;
    const isMac = target.result.os.tag == .macos;

    // sdl2
    if (isMac) {
        // Add SDL2, include path may vary
        // exe.addIncludePath(.{ .path = "/usr/local/include/SDL2"});
        // exe.linkSystemLibrary("sdl2");

        exe.addFrameworkPath(b.path("3rdparty/sdl2/osx"));
        // exe.linkSystemLibrary("sdl2");
        exe.linkFramework("SDL2");
        exe.addRPath(b.path("3rdparty/sdl2/osx"));
        exe.linkFramework("Foundation");
        exe.linkFramework("CoreFoundation");
        exe.linkFramework("Cocoa");
        exe.linkFramework("QuartzCore");
        exe.linkFramework("OpenGL");
        exe.linkFramework("IOKit");
        exe.linkFramework("Metal");
    } else if (isWindows) {
        exe.addIncludePath(b.path("3rdparty/sdl2/windows/include"));
        exe.addLibraryPath(b.path("3rdparty/sdl2/windows/win64"));
        exe.linkSystemLibrary("sdl2");
        exe.linkSystemLibrary("opengl32");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("winmm");
        exe.linkSystemLibrary("setupapi");
        exe.linkSystemLibrary("ole32");
        exe.linkSystemLibrary("oleaut32");
        exe.linkSystemLibrary("imm32");
        exe.linkSystemLibrary("version");
    }

    // zmath - not a package yet, so manually make the module
    const zmath_options_step = b.addOptions();
    zmath_options_step.addOption(
        bool,
        "enable_cross_platform_determinism",
        true,
    );
    const zmath_options = zmath_options_step.createModule();
    const zmath = b.addModule("zmath", .{
        .root_source_file = b.path("3rdparty/zmath/src/zmath.zig"),
        .imports = &.{
            .{ .name = "zmath_options", .module = zmath_options },
        },
    });
    // exe.addModule("zmath", zmath);
    exe.root_module.addImport("zmath", zmath);

    // zigstr dependency, pulled via build.zig.zon
    const zigstr = b.dependency("zigstr", .{
        .target = target,
        .optimize = optimize,
    });
    // exe.addModule("zigstr", zigstr.module("zigstr"));
    exe.root_module.addImport("zigstr", zigstr.module("zigstr"));

    // Link the bgfx libs
    bx.link(b, exe, target, optimize);
    bimg.link(b, exe, target, optimize);
    bgfx.link(b, exe, target, optimize);

    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("c++");

    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);

    // copy dll
    if (isWindows) {
        const sdl2_dll = switch (target.result.cpu.arch) {
            .x86_64 => "3rdparty/sdl2/windows/win64/SDL2.dll",
            .x86 => "3rdparty/sdl2/windows/win32/SDL2.dll",
            else => null,
        };

        if (sdl2_dll) |dll_path| {
            const sdl2_dll_step = b.addInstallBinFile(b.path(dll_path), "SDL2.dll");
            b.getInstallStep().dependOn(&sdl2_dll_step.step);

            // if (b.args) |args| {
            //     args.step.dependOn(&sdl2_dll_step.step);
            // }
        }
    }

    // build the shader compiler
    const shader_compiler_exe = sc.build(b, target, optimize);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    addShaderCompilerTaskToBuild(b, shader_compiler_exe, target) catch {};
}

pub fn addShaderCompilerTaskToBuild(b: *std.Build, shader_compiler_exe: *CompileStep, target: std.Build.ResolvedTarget) !void {
    const compile_shaders_step = b.step("shaders", "Compile Shaders");
    compile_shaders_step.dependOn(b.getInstallStep());

    var files = std.ArrayList([]const u8).init(b.allocator);
    defer files.deinit();

    // TODO: Maybe iterate over all directories under shaders?
    const shader_dir = "assets/shaders/cubes";

    // Find all of the shader files
    var dir = try std.fs.cwd().openDir(shader_dir, .{ .iterate = true });
    var it = dir.iterate();
    while (try it.next()) |file| {
        if (file.kind != .file) {
            continue;
        }

        const path = try std.fs.path.join(b.allocator, &[_][]const u8{ shader_dir, file.name });
        const extension = std.fs.path.extension(file.name);

        // Only consider .sc files
        if (!std.mem.eql(u8, extension, ".sc"))
            continue;

        // Ignore the varying definition file
        if (std.mem.startsWith(u8, file.name, "varying.def"))
            continue;

        // Figure out the type of shader this is
        var shader_type: []const u8 = "";
        if (std.mem.startsWith(u8, file.name, "fs_"))
            shader_type = "fragment";
        if (std.mem.startsWith(u8, file.name, "vs_"))
            shader_type = "vertex";

        // Stop if no type was found!
        if (shader_type.len == 0)
            continue;

        // Setup the output path
        const out_path = try std.mem.concat(b.allocator, u8, &[_][]const u8{ path, ".bin" });

        // Run the built shader compiler on this file, with a bunch of args set
        const run_cmd = b.addRunArtifact(shader_compiler_exe);
        compile_shaders_step.dependOn(&run_cmd.step);

        var args = std.ArrayList([]const u8).init(b.allocator);
        defer args.deinit();

        run_cmd.addArg("-f");
        run_cmd.addArg(path);

        run_cmd.addArg("-o");
        run_cmd.addArg(out_path);

        run_cmd.addArg("-i");
        run_cmd.addArg("assets/shaders/include");

        run_cmd.addArg("--type");
        run_cmd.addArg(shader_type);

        const isWindows = target.result.os.tag == .windows;
        const isMac = target.result.os.tag == .macos;

        // TODO: add more platforms
        run_cmd.addArg("--platform");
        if (isMac)
            run_cmd.addArg("osx");
        if (isWindows)
            run_cmd.addArg("windows");

        // for now we assume GLSL 400
        run_cmd.addArg("--profile");
        run_cmd.addArg("150");
    }
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
