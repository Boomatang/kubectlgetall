const std = @import("std");

const clap = @import("clap");

const db = @import("database.zig");
const logging = @import("log.zig");
const types = @import("types.zig");
const table = @import("table.zig");
const utils = @import("utils.zig");

pub fn getMain(io: std.Io, gpa: std.mem.Allocator, iter: *std.process.Args.Iterator) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-n, --namespace <STR>   Namespace to get resources from.
        \\-A, --all-namespaces If present, list all objects across all namespaces. Specifying --namespace will be ignored.
        \\-s, --sort Prints the resources in order.
        \\-e, --exclude <STR>... Exclude crd types. Multiple can be excluded eg: "-e <CRD> -e <CRD>"
        \\-o, --output <OUTPUT> Changes the output format of the results. [default: tty, tty|json|sqlite]
        \\-d, --database <PATH> Path to the sqlite file to save the results. If the files does not exist it will be created.
        \\-l, --label <STR> Set the label that will be saved with entries when using the --database option.
        \\--log-level <LEVEL> Set the log level. All logs are saved to file. Possible values are (debug, info, warn, error). Default level is warn.
        \\
    );

    const parsers = comptime .{
        .OUTPUT = clap.parsers.enumeration(types.Output),
        .STR = clap.parsers.string,
        .PATH = clap.parsers.string,
        .LEVEL = clap.parsers.enumeration(logging.Level),
    };

    // Initialize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also pass `.{}` to `clap.parse` if you don't
    // care about the extra information `Diagnostic` provides.
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, parsers, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    var namespace: []const u8 = &[_]u8{};
    var allNamespaces = false;
    var sort = false;
    var output = types.Output.tty;
    var database: []const u8 = &[_]u8{};
    var label: []const u8 = &[_]u8{};
    var exclude: ?[]const []const u8 = null;

    if (res.args.help != 0)
        return clap.helpToFile(io, .stdout(), clap.Help, &params, .{});

    if (res.args.namespace) |n| {
        namespace = n;
    }

    if (res.args.@"all-namespaces" == 1) {
        allNamespaces = true;
    }

    if (res.args.sort == 1) {
        sort = true;
    }

    if (res.args.output) |o| {
        output = o;
    }

    if (res.args.database) |d| {
        database = d;
    }

    if (res.args.label) |l| {
        label = l;
    }

    if (res.args.@"log-level") |l| {
        logging.setLogLevel(l);
    }

    if (res.args.exclude.len > 0) {
        exclude = res.args.exclude;
    }
    const config = types.Config{
        .namespace = namespace,
        .all = allNamespaces,
        .sort = sort,
        .exclude = exclude,
        .output = output,
        .database = database,
        .label = label,
        .timestamp = std.Io.Timestamp.now(io, .real).toSeconds(),
    };

    std.log.debug("{f}", .{config});

    var crdTypes = getCrdList(io, gpa) catch |err| switch (err) {
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
        std.mem.sort([]const u8, crdTypes.items, {}, compareStrings);
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

        const resource = getCRJson(io, gpa, config, line) catch |err| switch (err) {
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

fn getCRJson(io: std.Io, allocator: std.mem.Allocator, config: types.Config, crd: []const u8) !types.ResourceList {
    const initialcmd = &[_][]const u8{ "kubectl", "get", "--ignore-not-found", crd, "--output", "json" };

    var cmd: std.ArrayList([]const u8) = .empty;
    defer cmd.deinit(allocator);

    try cmd.appendSlice(allocator, initialcmd);
    if (config.all) {
        try cmd.append(allocator, "--all-namespaces");
    } else {
        try cmd.append(allocator, "--namespace");
        try cmd.append(allocator, config.namespace);
    }

    const ownedCmd = try cmd.toOwnedSlice(allocator);
    defer allocator.free(ownedCmd);

    const result = std.process.run(allocator, io, .{
        .argv = ownedCmd,
    }) catch |err| {
        std.log.err("Failed to run kubectl: {}", .{err});
        return err;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.exited != 0) {
        return error.BadExit;
    }

    if (result.stdout.len == 0) {
        return error.NoData;
    }

    const parsed: std.json.Parsed(types.ResourceList) = std.json.parseFromSlice(types.ResourceList, allocator, result.stdout, .{ .ignore_unknown_fields = true }) catch |err| switch (err) {
        std.json.ParseFromValueError.MissingField => return error.NotFound,
        else => return err,
    };

    defer {
        parsed.deinit();
    }

    return parsed.value.clone(allocator);
}

fn compareStrings(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn getCrdList(io: std.Io, gpa: std.mem.Allocator) !std.ArrayList([]const u8) {
    const cmd = [_][]const u8{ "kubectl", "api-resources", "--verbs=list", "--namespaced", "-o", "name" };
    const result = std.process.run(gpa, io, .{
        .argv = &cmd,
    }) catch |err| {
        std.log.err("Failed to run kubectl: {}", .{err});
        return err;
    };
    defer {
        gpa.free(result.stdout);
        gpa.free(result.stderr);
    }

    if (result.term.exited != 0) {
        std.log.debug("stdout: {s}. stderr: {s}", .{ result.stdout, result.stderr });
        return error.BadExit;
    }
    var lines: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (lines.items) |item| {
            gpa.free(item);
        }
        lines.deinit(gpa);
    }

    var iter = std.mem.splitScalar(u8, result.stdout, '\n');
    while (iter.next()) |line| {
        if (line.len > 0) {
            const owned = try gpa.dupe(u8, line);
            errdefer gpa.free(owned);
            try lines.append(gpa, owned);
        }
    }

    return lines;
}
