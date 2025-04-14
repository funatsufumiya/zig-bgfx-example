const std = @import("std");

const bx = @import("build_bx.zig");
const bimg = @import("build_bimg.zig");

const bgfx_path = "3rdparty/bgfx/";

const CompileStep = std.Build.Step.Compile;

var framework_dir: ?[]u8 = null;

pub fn link(b: *std.Build, exe: *CompileStep, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const lib = buildLibrary(b, exe, target, optimize);
    addBgfxIncludes(b, exe);
    exe.linkLibrary(lib);
}

fn buildLibrary(b: *std.Build, exe: *CompileStep, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *CompileStep {
    const isMac = target.result.os.tag == .macos;
    const isLinux = target.result.os.tag == .linux;

    const linux_cxx_options = [_][]const u8{
        "-fno-strict-aliasing",
        "-fno-exceptions",
        "-fno-rtti",
        "-ffast-math",
        "-DBX_CONFIG_DEBUG",
        "-DBGFX_CONFIG_USE_TINYSTL=0",
        "-DBGFX_CONFIG_MULTITHREADED=0",
        "-DBGFX_CONFIG_RENDERER_DIRECT3D9=0",
        "-DBGFX_CONFIG_RENDERER_DIRECT3D11=0",
        "-DBGFX_CONFIG_RENDERER_DIRECT3D12=0",
        "-DBGFX_CONFIG_RENDERER_GNM=0",
        "-DBGFX_CONFIG_RENDERER_OPENGLES=0",
    };

    const default_cxx_options = [_][]const u8{
        "-fno-strict-aliasing",
        "-fno-exceptions",
        "-fno-rtti",
        "-ffast-math",
        "-DBX_CONFIG_DEBUG",
        "-DBGFX_CONFIG_USE_TINYSTL=0",
        "-DBGFX_CONFIG_MULTITHREADED=0", // OSX does not support multithreaded rendering
    };

    const cxx_options = if (isLinux) &linux_cxx_options else &default_cxx_options;

    const bgfx_module = exe.step.owner.createModule(.{
        .root_source_file = b.path(bgfx_path ++ "bindings/zig/bgfx.zig"),
    });

    const bgfx_lib = exe.step.owner.addStaticLibrary(.{
        .name = "bgfx",
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("bgfx", bgfx_module);

    bgfx_lib.addIncludePath(b.path(bgfx_path ++ "include/"));
    bgfx_lib.addIncludePath(b.path(bgfx_path ++ "3rdparty/"));
    bgfx_lib.addIncludePath(b.path(bgfx_path ++ "3rdparty/directx-headers/include/directx/"));
    bgfx_lib.addIncludePath(b.path(bgfx_path ++ "3rdparty/khronos/"));
    bgfx_lib.addIncludePath(b.path(bgfx_path ++ "src/"));

    if (isMac) {
        bgfx_lib.addCSourceFile(.{ .file = b.path(bgfx_path ++ "src/amalgamated.mm"), .flags = cxx_options });
        bgfx_lib.linkFramework("Foundation");
        bgfx_lib.linkFramework("CoreFoundation");
        bgfx_lib.linkFramework("Cocoa");
        bgfx_lib.linkFramework("QuartzCore");
    } else {
        bgfx_lib.addCSourceFile(.{ .file = b.path(bgfx_path ++ "src/amalgamated.cpp"), .flags = cxx_options });
    }

    if (isLinux) {
        const bx_path = "3rdparty/bx/";
        bgfx_lib.addIncludePath(b.path(bx_path ++ "include/compat/linux"));
    }

    bgfx_lib.want_lto = false;
    bgfx_lib.linkSystemLibrary("c");
    bgfx_lib.linkSystemLibrary("c++");
    bx.link(b, bgfx_lib, target, optimize);
    bimg.link(b, bgfx_lib, target, optimize);

    const bgfx_lib_artifact = exe.step.owner.addInstallArtifact(bgfx_lib, .{});
    exe.step.owner.getInstallStep().dependOn(&bgfx_lib_artifact.step);

    return bgfx_lib;
}

fn addBgfxIncludes(b: *std.Build, exe: *CompileStep) void {
    exe.addIncludePath(b.path(bgfx_path ++ "include/"));
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
