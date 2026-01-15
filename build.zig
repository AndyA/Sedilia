const std = @import("std");

fn benchmark(
    b: *std.Build,
    comptime name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const bm_exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/" ++ name ++ ".zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(bm_exe);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sedilia_exe = b.addExecutable(.{
        .name = "sedilia",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sedilia.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    const rdb_bindings = b.dependency("rocksdb", .{
        .target = target,
        .optimize = optimize,
    }).module("bindings");
    sedilia_exe.root_module.addImport("rocksdb", rdb_bindings);

    b.installArtifact(sedilia_exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(sedilia_exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = sedilia_exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");

    test_step.dependOn(&run_exe_tests.step);
    benchmark(b, "bm-codec", target, optimize);
}
