const clap = @import("clap");
const std = @import("std");
const build_options = @import("build_options");

const db = @import("database.zig");
const types = @import("types.zig");
const table = @import("table.zig");

pub const std_options: std.Options = .{
    // Keep compile-time logging permissive; runtime filter in `log`.
    .log_level = .debug,
    .logFn = log,
};

pub var log_level: std.log.Level = .info;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = comptime blk: {
        if (scope == .default)
            break :blk "[" ++ level.asText() ++ "] ";
        break :blk "[" ++ level.asText() ++ "][" ++ @tagName(scope) ++ "] ";
    };

    if (@intFromEnum(level) <= @intFromEnum(log_level)) {
        std.debug.print(prefix ++ format ++ "\n", args);
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-n, --namespace <STR>   Namespace to get resources from.
        \\-A, --all-namespaces If present, list all objects across all namespaces. Specifing --namespace will be ignored.
        \\-s, --sort Prints the resources in order.
        \\-e, --exclude <STR>... Exclude crd types. Multiple can be excluded eg: "-e <CRD> -e <CRD>"
        \\-o, --output <OUTPUT> Changes the output format of the results. [default: tty, tty|json|sqlite]
        \\-d, --database <PATH> Path to the sqlite file to save the results. If the files does not exist it will be created.
        \\-l, --label <STR> Set the label that will be saved with entries when using the --database option.
        \\--log-level <LEVEL> Set the log level. All logs are saved to file. Possible values are (debug, info, warn, error). Defualt level is warn.
        \\--version Display verson, and exit.
        \\
    );

    const parsers = comptime .{
        .OUTPUT = clap.parsers.enumeration(types.Output),
        .STR = clap.parsers.string,
        .PATH = clap.parsers.string,
        .LEVEL = clap.parsers.enumeration(types.Level),
    };

    // Initialize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also pass `.{}` to `clap.parse` if you don't
    // care about the extra information `Diagnostic` provides.
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    var namespace: []const u8 = &[_]u8{};
    var allNamespaces = false;
    var sort = false;
    var output = types.Output.tty;
    var database: []const u8 = &[_]u8{};
    var label: []const u8 = &[_]u8{};
    var level = types.Level.warn;
    var exclude: ?[]const []const u8 = null;

    if (res.args.help != 0)
        return clap.helpToFile(init.io, .stdout(), clap.Help, &params, .{});

    if (res.args.version != 0) {
        std.log.info("{s}, {s}", .{ build_options.name, build_options.version });
        std.process.exit(0);
    }

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
        level = l;
    }

    if (res.args.exclude.len > 0) {
        exclude = res.args.exclude;
    }

    switch (level) {
        .debug => log_level = std.log.Level.debug,
        .@"error" => log_level = std.log.Level.err,
        .info => log_level = std.log.Level.info,
        .warn => log_level = std.log.Level.warn,
    }
    const config = types.Config{
        .namespace = namespace,
        .all = allNamespaces,
        .sort = sort,
        .exclude = exclude,
        .output = output,
        .database = database,
        .label = label,
        .logLevel = level,
        .timestamp = std.Io.Timestamp.now(init.io, .real).toSeconds(),
    };

    std.log.debug("{f}", .{config});

    var crdTypes = getCrdList(init.io, allocator) catch |err| switch (err) {
        error.BadExit => {
            std.log.err("Kubectl returned a none zero exit code", .{});
            std.process.exit(1);
        },
        else => return err,
    };
    defer {
        for (crdTypes.items) |item| {
            allocator.free(item);
        }
        crdTypes.deinit(allocator);
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
            const value = m.get(key.*).?;
            value.deinit(allocator);
        }
        m.deinit();
    };
    if (config.output == .json) {
        map = std.StringHashMap(types.ResourceList).init(allocator);
        const v: u32 = if (crdTypes.items.len <= std.math.maxInt(u32)) @intCast(crdTypes.items.len) else std.math.maxInt(u32);
        if (map) |*m| try m.ensureTotalCapacity(v);
    }
    for (crdTypes.items) |line| {
        if (contains(config.exclude, line)) {
            std.log.debug("filter out: {s}", .{line});

            continue;
        }

        const resource = getCRJson(init.io, allocator, config, line) catch |err| switch (err) {
            error.NoData => {
                continue;
            },
            else => return err,
        };
        switch (config.output) {
            .tty => {
                defer {
                    resource.deinit(allocator);
                }
                try table.print(init.io, resource);
            },
            .sqlite => {
                defer {
                    resource.deinit(allocator);
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
            const text = try item.toJson(allocator);
            defer allocator.free(text);
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

fn contains(haystack: ?[]const []const u8, needle: []const u8) bool {
    if (haystack) |stack| {
        for (stack) |s| {
            if (std.mem.eql(u8, s, needle)) return true;
        }
    }

    return false;
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

fn getCrdList(io: std.Io, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    const cmd = [_][]const u8{ "kubectl", "api-resources", "--verbs=list", "--namespaced", "-o", "name" };
    const result = std.process.run(allocator, io, .{
        .argv = &cmd,
    }) catch |err| {
        std.log.err("Failed to run kubectl: {}", .{err});
        return err;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.exited != 0) {
        std.log.debug("stdout: {s}. stderr: {s}", .{ result.stdout, result.stdout });
        return error.BadExit;
    }
    var lines: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (lines.items) |item| {
            allocator.free(item);
        }
        lines.deinit(allocator);
    }

    var iter = std.mem.splitScalar(u8, result.stdout, '\n');
    while (iter.next()) |line| {
        if (line.len > 0) {
            const owned = try allocator.dupe(u8, line);
            errdefer allocator.free(owned);
            try lines.append(allocator, owned);
        }
    }

    return lines;
}
