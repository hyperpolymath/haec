// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// HAEC FFI build graph (Zig 0.15.2+).
//
// `zig build` installs static and shared libhaec artifacts.
// `zig build test` runs unit tests and C-boundary integration tests.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const shared_library = b.addLibrary(.{
        .name = "haec",
        .linkage = .dynamic,
        .root_module = shared_module,
    });
    b.installArtifact(shared_library);

    const static_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const static_library = b.addLibrary(.{
        .name = "haec",
        .linkage = .static,
        .root_module = static_module,
    });
    b.installArtifact(static_library);

    const unit_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const unit_tests = b.addTest(.{ .root_module = unit_module });

    const integration_module = b.createModule(.{
        .root_source_file = b.path("test/integration_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const integration_tests = b.addTest(.{ .root_module = integration_module });
    integration_tests.linkLibrary(static_library);

    const test_step = b.step("test", "Run unit and C-boundary integration tests");
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);
    test_step.dependOn(&b.addRunArtifact(integration_tests).step);
}
