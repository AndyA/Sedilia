const std = @import("std");

fn utility(
    b: *std.Build,
    comptime name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const bm_exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/" ++ name ++ ".zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(bm_exe);
    return bm_exe;
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

    const mule_exe = utility(b, "mule", target, optimize);
    const mule_tests = b.addTest(.{
        .root_module = mule_exe.root_module,
    });

    const run_mule_tests = b.addRunArtifact(mule_tests);
    const test_step = b.step("test", "Run tests");

    test_step.dependOn(&run_mule_tests.step);

    _ = utility(b, "jfilt", target, optimize);
    _ = utility(b, "nd-loader", target, optimize);

    // Benchmarks
    _ = utility(b, "bm-codec", target, optimize);
    const bm_rocks_exe = utility(b, "bm-rocks", target, optimize);
    bm_rocks_exe.root_module.addImport("rocksdb", rdb_bindings);
}
