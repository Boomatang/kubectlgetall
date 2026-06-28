const std = @import("std");
const clap = @import("clap");

const args = @import("args.zig");
const cluster = @import("cluster.zig");
const db = @import("database.zig");
const help = @import("help.zig");
const logging = @import("log.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");

pub fn cmd(io: std.Io, gpa: std.mem.Allocator, iter: *std.process.Args.Iterator) !void {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &args.snapshot_params, args.snapshot_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try help.snapshot(io, .stdout());
        std.process.exit(0);
    }

    if (res.args.@"log-level") |l| {
        logging.setLogLevel(l);
    }

    var config = types.SnapshotConfig{
        .database = res.args.database orelse return error.MissingDatabase,
        .label = res.args.label orelse return error.MissingLabel,
        .exclude = if (res.args.exclude.len > 0) res.args.exclude else null,
        .all = if (res.args.@"all-namespaces" == 1) true else false,
        .namespace = if (res.args.namespace) |n| n else "",
        .startTime = std.Io.Timestamp.now(io, .real).toSeconds(),
    };

    if (res.args.delay) |v| config.delay = @intCast(v);
    if (res.args.limit) |v| config.limit = @intCast(v);
    if (res.args.count) |v| config.count = v;

    std.log.debug("{f}", .{config});

    try db.init(config.database);

    var run = true;
    const endTime = config.startTime + config.limit;
    while (run) {
        if (config.count > 0) {
            std.log.info("Starting snapshot run {} of {}.", .{ config.interation + 1, config.count });
        } else {
            std.log.info("Starting snapshot run {}.", .{config.interation + 1});
        }
        std.log.debug("{f}", .{config});

        var crdTypes = cluster.getCrdList(io, gpa) catch |err| switch (err) {
            error.BadExit => {
                std.log.err("Kubectl returned a none zero exit code", .{});
                std.process.exit(1);
            },
            else => return err,
        };
        defer {
            for (crdTypes.items) |item| {
                gpa.free(item);
            }
            crdTypes.deinit(gpa);
        }
        std.log.info("Total number of CRD types found {}.", .{crdTypes.items.len});

        const timestamp = std.Io.Timestamp.now(io, .real).toSeconds();
        const label = try std.fmt.allocPrint(gpa, "{s}-{}", .{ config.label, config.interation });
        defer gpa.free(label);

        for (crdTypes.items) |line| {
            if (utils.matchedExclude(config.exclude, line)) |matched| {
                std.log.debug("excluding resource {s} matched by -e {s}", .{ line, matched });
                continue;
            }

            const resource = cluster.getCRJson(io, gpa, config, line) catch |err| switch (err) {
                error.NoData => {
                    continue;
                },
                else => return err,
            };
            defer resource.deinit(gpa);

            if (resource.items.len > 0) {
                if (utils.matchedExclude(config.exclude, resource.items[0].kind)) |matched| {
                    std.log.debug("excluding {s}/{s} matched by -e {s}", .{ resource.items[0].apiVersion, resource.items[0].kind, matched });
                    resource.deinit(gpa);
                    continue;
                }
            }

            try db.add(resource, label, timestamp);
        }

        // Below are the steps required to quit the loops when required.
        config.interation += 1;
        if (config.count != 0 and config.count <= config.interation) {
            std.log.info("Run count limit reached.", .{});
            run = false;
            continue;
        }

        const nextTime = if (config.limit > 0) std.Io.Timestamp.now(io, .real).toSeconds() + config.delay else endTime - 1;

        if (endTime < nextTime) {
            run = false;
            std.log.info("Next wait will take longer than time limit allows, exiting early.", .{});
            continue;
        }

        std.log.info("Waiting {} seconds before next snapshot.", .{config.delay});
        try std.Io.sleep(io, std.Io.Duration.fromSeconds(config.delay), .real);
    }
}
