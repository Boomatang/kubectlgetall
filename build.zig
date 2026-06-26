const std = @import("std");
const zon = @import("build.zig.zon");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.
    //
    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    const sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // business logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "kubectlgetall",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{},
        }),
    });

    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);
    options.addOption([]const u8, "name", @tagName(zon.name));

    exe.root_module.addOptions("build_options", options);

    exe.root_module.addImport("clap", clap.module("clap"));
    exe.root_module.addImport("sqlite", sqlite.module("sqlite"));

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.

    // Change log configuration
    const changelog_cmd = b.addSystemCommand(&.{
        "towncrier",
        "build",
        "--draft",
        "--version",
        zon.version,
    });
    const changelog_step = b.step("changelog_draft", "Build changelog draft");
    changelog_step.dependOn(&changelog_cmd.step);

    const changelog_release_cmd = b.addSystemCommand(&.{
        "towncrier",
        "build",
        "--version",
        zon.version,
    });
    const changelog_release_step = b.step("changelog_release", "Build changelog draft");
    changelog_release_step.dependOn(&changelog_release_cmd.step);

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
