const std = @import("std");

const CompileStep = std.Build.Step.Compile;

const bx_path = "3rdparty/bx/";

pub fn link(b: *std.Build, exe: *CompileStep, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const lib = buildLibrary(b, exe, target, optimize);
    addBxIncludes(b, exe, target);
    exe.linkLibrary(lib);
}

fn buildLibrary(b: *std.Build, exe: *CompileStep, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *CompileStep {
    const cxx_options = [_][]const u8{
        "-fno-strict-aliasing",
        "-fno-exceptions",
        "-fno-rtti",
        "-ffast-math",
        "-DBX_CONFIG_DEBUG",
    };

    const bx_lib = exe.step.owner.addStaticLibrary(.{ .name = "bx", .target = target, .optimize = optimize });

    const isMac = target.result.os.tag == .macos;

    addBxIncludes(b, bx_lib, target);
    if (isMac) {
        bx_lib.linkFramework("CoreFoundation");
        bx_lib.linkFramework("Foundation");
    }
    bx_lib.addCSourceFile(.{ .file = b.path(bx_path ++ "src/amalgamated.cpp"), .flags = &cxx_options });
    bx_lib.want_lto = false;
    bx_lib.linkSystemLibrary("c");
    bx_lib.linkSystemLibrary("c++");

    const bx_lib_artifact = exe.step.owner.addInstallArtifact(bx_lib, .{});
    exe.step.owner.getInstallStep().dependOn(&bx_lib_artifact.step);
    return bx_lib;
}

fn addBxIncludes(b: *std.Build, exe: *CompileStep, target: std.Build.ResolvedTarget) void {
    var compat_include: []const u8 = "";

    const isWindows = target.result.os.tag == .windows;
    const isMac = target.result.os.tag == .macos;
    const isLinux = target.result.os.tag == .linux;

    if (isWindows) {
        compat_include = bx_path ++ "include/compat/mingw/";
    } else if (isMac) {
        compat_include = bx_path ++ "include/compat/osx/";
    } else if (isLinux) {
        compat_include = bx_path ++ "include/compat/linux/";
    }

    exe.addIncludePath(b.path(compat_include));
    exe.addIncludePath(b.path(bx_path ++ "include/"));
    exe.addIncludePath(b.path(bx_path ++ "3rdparty"));
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
