const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap = b.dependency("clap", .{});
    const zigwin32 = b.dependency("zigwin32", .{}).module("win32");

    const test_step = b.step("test", "Run all tests");
    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("zigwin32", zigwin32);
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const exe = b.addExecutable(.{
        .name = "rb",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("clap", clap.module("clap"));
    exe.root_module.addImport("zigwin32", zigwin32);
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
    const release_exe = b.addExecutable(.{
        .name = "release",
        .root_source_file = b.path("scripts/release.zig"),
        .target = target,
        .optimize = optimize,
    });
    const release_cmd = b.addRunArtifact(release_exe);
    release_step.dependOn(&release_cmd.step);
}
