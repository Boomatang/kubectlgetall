const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    const sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "kubectlgetall",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);
    options.addOption([]const u8, "name", @tagName(zon.name));

    exe.root_module.addOptions("build_options", options);

    exe.root_module.addImport("clap", clap.module("clap"));
    exe.root_module.addImport("sqlite", sqlite.module("sqlite"));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);

    // Set Up Changie Commands
    const changie_bin = get_changie_bin(b) orelse return;

    // Changie Version
    const changie_version = std.Build.Step.Run.create(b, "run changie");
    changie_version.addFileArg(changie_bin);
    changie_version.addArg("--version");
    const changie_version_cmd = b.step("changie:version", "print the changie version");
    changie_version_cmd.dependOn(&changie_version.step);

    // Changie Add
    const changie_add = std.Build.Step.Run.create(b, "run changie");
    changie_add.addFileArg(changie_bin);
    changie_add.addArg("new");
    const changie_add_cmd = b.step("changie:add", "Add change log fragment");
    changie_add_cmd.dependOn(&changie_add.step);

    // Changie batch
    const changie_batch = std.Build.Step.Run.create(b, "run changie");
    changie_batch.addFileArg(changie_bin);
    changie_batch.addArg("batch");
    changie_batch.addArg(zon.version);
    const changie_batch_cmd = b.step("changie:batch", "Batch fragments for a release");
    changie_batch_cmd.dependOn(&changie_batch.step);

    // Changie batch
    const changie_merge = std.Build.Step.Run.create(b, "run changie");
    changie_merge.addFileArg(changie_bin);
    changie_merge.addArg("merge");
    const changie_merge_cmd = b.step("changie:merge", "Merge all changes into CHANGLOG.md");
    changie_merge_cmd.dependOn(&changie_merge.step);

    // Build release command
    const release_step = b.step("release", "Build release archives");
    const release_checks = ReleaseChecksStep.create(b);

    const release_targets = [_]ReleaseTarget{
        .{ .os_tag = .linux, .arch = .x86_64, .os_name = "linux", .arch_name = "amd64" },
        .{ .os_tag = .linux, .arch = .aarch64, .os_name = "linux", .arch_name = "arm64" },
        .{ .os_tag = .macos, .arch = .x86_64, .os_name = "darwin", .arch_name = "amd64" },
        .{ .os_tag = .macos, .arch = .aarch64, .os_name = "darwin", .arch_name = "arm64" },
    };

    for (release_targets) |release_target| {
        const resolved_target = b.resolveTargetQuery(.{
            .cpu_arch = release_target.arch,
            .os_tag = release_target.os_tag,
        });
        const release_exe = addReleaseExecutable(
            b,
            resolved_target,
            optimize,
            clap,
            sqlite,
        );

        const archive_name = b.fmt("{s}_{s}_{s}_{s}.tar.gz", .{
            @tagName(zon.name),
            zon.version,
            release_target.os_name,
            release_target.arch_name,
        });
        const dist_dir = "dist";
        const staging_dir = b.fmt("{s}/stage_{s}_{s}", .{
            dist_dir,
            release_target.os_name,
            release_target.arch_name,
        });

        const make_staging = b.addSystemCommand(&.{ "mkdir", "-p", staging_dir });

        const copy_bin = b.addSystemCommand(&.{"cp"});
        copy_bin.addFileArg(release_exe.getEmittedBin());
        copy_bin.addArg(staging_dir);

        const copy_docs = b.addSystemCommand(&.{
            "cp",
            "README.md",
            "CHANGELOG.md",
            staging_dir,
        });

        const tar_cmd = b.addSystemCommand(&.{
            "tar",
            "-czf",
            b.fmt("{s}/{s}", .{ dist_dir, archive_name }),
            "-C",
            staging_dir,
            ".",
        });

        copy_bin.step.dependOn(&release_exe.step);
        copy_bin.step.dependOn(&make_staging.step);
        copy_bin.step.dependOn(&release_checks.step);
        copy_docs.step.dependOn(&make_staging.step);
        copy_docs.step.dependOn(&release_checks.step);
        tar_cmd.step.dependOn(&make_staging.step);
        tar_cmd.step.dependOn(&copy_docs.step);
        tar_cmd.step.dependOn(&copy_bin.step);
        tar_cmd.step.dependOn(&release_checks.step);
        release_step.dependOn(&tar_cmd.step);
    }
}

const ReleaseTarget = struct {
    os_tag: std.Target.Os.Tag,
    arch: std.Target.Cpu.Arch,
    os_name: []const u8,
    arch_name: []const u8,
};

const ReleaseChecksStep = struct {
    step: std.Build.Step,
    version: []const u8,

    pub fn create(b: *std.Build) *ReleaseChecksStep {
        const checks = b.allocator.create(ReleaseChecksStep) catch @panic("OOM");
        checks.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "release_checks",
                .owner = b,
                .makeFn = make,
            }),
            .version = b.dupe(zon.version),
        };

        return checks;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
        _ = step;
        _ = options;
    }
};

fn addReleaseExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    clap: *std.Build.Dependency,
    sqlite: *std.Build.Dependency,
) *std.Build.Step.Compile {
    _ = optimize;
    const release_optimize: std.builtin.OptimizeMode = .ReleaseSmall;
    const exe = b.addExecutable(.{
        .name = @tagName(zon.name),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = release_optimize,
        }),
    });

    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);
    options.addOption([]const u8, "name", @tagName(zon.name));

    exe.root_module.addOptions("build_options", options);

    exe.root_module.addImport("clap", clap.module("clap"));
    exe.root_module.addImport("sqlite", sqlite.module("sqlite"));

    return exe;
}

fn get_changie_bin(b: *std.Build) ?std.Build.LazyPath {
    const host = b.graph.host.result;
    const name = switch (host.os.tag) {
        .linux => switch (host.cpu.arch) {
            .x86_64 => "changie_linux_amd64",
            .aarch64 => "changie_linux_arm64",
            else => @panic("unsupported cpu arch"),
        },
        .macos => switch (host.cpu.arch) {
            .x86_64 => "changie_darwin_amd64",
            .aarch64 => "changie_darwin_arm64",
            else => @panic("unsupported cpu arch"),
        },

        else => @panic("unsupported os"),
    };

    if (b.lazyDependency(name, .{})) |dep| {
        return dep.path("changie");
    } else {
        return null;
    }
}
