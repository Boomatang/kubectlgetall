const std = @import("std");

const clap = @import("clap");

const db = @import("database.zig");
const logging = @import("log.zig");
const types = @import("types.zig");
const table = @import("table.zig");
const utils = @import("utils.zig");
const help = @import("help.zig");
const args = @import("args.zig");
const cluster = @import("cluster.zig");

pub fn getMain(io: std.Io, gpa: std.mem.Allocator, iter: *std.process.Args.Iterator) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &args.get_params, args.get_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try help.get(io, .stdout());
        std.process.exit(0);
    }

    if (res.args.@"log-level") |l| {
        logging.setLogLevel(l);
    }

    const config = types.Config{
        .namespace = if (res.args.namespace) |v| v else "",
        .all = (res.args.@"all-namespaces" == 1),
        .sort = (res.args.sort == 1),
        .exclude = if (res.args.exclude.len > 0) res.args.exclude else null,
        .output = if (res.args.output) |v| v else .tty,
        .database = if (res.args.database) |v| v else "",
        .label = if (res.args.label) |v| v else "",
        .timestamp = std.Io.Timestamp.now(io, .real).toSeconds(),
    };

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

    if (config.sort) {
        std.mem.sort([]const u8, crdTypes.items, {}, utils.compareStrings);
    }

    if (config.output == .sqlite) {
        if (config.database.len == 0) {
            std.log.err("--database must be set to use output type of sqlite", .{});
            std.process.exit(1);
        }
        try db.init(config.database);
    }
    std.log.info("Total number of CRD types found {}.", .{crdTypes.items.len});
    var map: ?std.StringHashMap(types.ResourceList) = null;
    defer if (map) |*m| {
        var it = m.keyIterator();
        while (it.next()) |key| {
            const value = m.get(key.*);
            if (value) |v| v.deinit(gpa);
        }
        m.deinit();
    };
    if (config.output == .json) {
        map = std.StringHashMap(types.ResourceList).init(gpa);
        const v: u32 = if (crdTypes.items.len <= std.math.maxInt(u32)) @intCast(crdTypes.items.len) else std.math.maxInt(u32);
        if (map) |*m| try m.ensureTotalCapacity(v);
    }
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
        if (resource.items.len > 0) {
            if (utils.matchedExclude(config.exclude, resource.items[0].kind)) |matched| {
                std.log.debug("excluding {s}/{s} matched by -e {s}", .{ resource.items[0].apiVersion, resource.items[0].kind, matched });
                resource.deinit(gpa);
                continue;
            }
        }
        switch (config.output) {
            .tty => {
                defer {
                    resource.deinit(gpa);
                }
                try table.print(io, resource);
            },
            .sqlite => {
                defer {
                    resource.deinit(gpa);
                }
                try db.add(resource, config.label, config.timestamp);
            },
            .json => {
                if (map) |*m| {
                    try m.put(line, resource);
                }
            },
        }
    }

    if (map) |*m| {
        std.log.debug("map length: {}", .{m.count()});
        try stdout.print("{{", .{});

        var it = m.iterator();
        var count: usize = 1;
        while (it.next()) |key| {
            const item = key.value_ptr;
            const text = try item.toJson(gpa);
            defer gpa.free(text);
            try stdout.print("\"{s}\": {s}", .{ key.key_ptr.*, text });
            if (count < m.count()) {
                try stdout.print(",", .{});
                count += 1;
            }
        }

        try stdout.print("}}\n", .{});
        try stdout.flush();
    }
}
