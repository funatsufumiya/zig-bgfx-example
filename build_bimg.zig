const std = @import("std");
const bx = @import("build_bx.zig");
const bimg_path = "3rdparty/bimg/";

const CompileStep = std.Build.Step.Compile;

pub fn link(b: *std.Build, exe: *CompileStep, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const lib = buildLibrary(b, exe, target, optimize);
    addBimgIncludes(b, exe);
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

    const bimg_lib = exe.step.owner.addStaticLibrary(.{ .name = "bimg", .target = target, .optimize = optimize});
    addBimgIncludes(b, bimg_lib);
    bimg_lib.addIncludePath(b.path(bimg_path ++ "3rdparty/"));
    bimg_lib.addIncludePath(b.path(bimg_path ++ "3rdparty/astc-encoder/"));
    bimg_lib.addIncludePath(b.path(bimg_path ++ "3rdparty/astc-encoder/include/"));
    bimg_lib.addCSourceFiles(.{
        .files = &.{
            bimg_path ++ "src/image.cpp",
            bimg_path ++ "src/image_gnf.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_averages_and_directions.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_block_sizes.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_color_quantize.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_color_unquantize.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_compress_symbolic.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_compute_variance.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_decompress_symbolic.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_diagnostic_trace.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_entry.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_find_best_partitioning.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_ideal_endpoints_and_weights.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_image.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_integer_sequence.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_mathlib.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_mathlib_softfloat.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_partition_tables.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_percentile_tables.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_pick_best_endpoint_format.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_platform_isa_detection.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_quantization.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_symbolic_physical.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_weight_align.cpp",
            bimg_path ++ "3rdparty/astc-encoder/source/astcenc_weight_quant_xfer_tables.cpp",
        },
        .flags = &cxx_options,
    });
    bimg_lib.want_lto = false;
    bimg_lib.linkSystemLibrary("c");
    bimg_lib.linkSystemLibrary("c++");
    bx.link(b, bimg_lib, target, optimize);

    const bimg_lib_artifact = exe.step.owner.addInstallArtifact(bimg_lib, .{});
    exe.step.owner.getInstallStep().dependOn(&bimg_lib_artifact.step);

    return bimg_lib;
}

fn addBimgIncludes(b: *std.Build, exe: *CompileStep) void {
    exe.addIncludePath(b.path(bimg_path ++ "include/"));
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
