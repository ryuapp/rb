const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap = b.dependency("clap", .{});
    const zigwin32 = b.dependency("zigwin32", .{}).module("win32");

    const test_step = b.step("test", "Run all tests");

    // Create a module for the main source
    const main_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_module.addImport("zigwin32", zigwin32);

    const unit_tests = b.addTest(.{
        .root_module = main_module,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_tests.step);

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_module.addImport("clap", clap.module("clap"));
    exe_module.addImport("zigwin32", zigwin32);

    const exe = b.addExecutable(.{
        .name = "rb",
        .root_module = exe_module,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the cli");
    run_step.dependOn(&run_cmd.step);

    // Release step
    const release_step = b.step("release", "Run release script");
    const release_module = b.createModule(.{
        .root_source_file = b.path("scripts/release.zig"),
        .target = target,
        .optimize = optimize,
    });
    const release_exe = b.addExecutable(.{
        .name = "release",
        .root_module = release_module,
    });
    const release_cmd = b.addRunArtifact(release_exe);
    release_step.dependOn(&release_cmd.step);
}
