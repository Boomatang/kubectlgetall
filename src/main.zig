const clap = @import("clap");
const std = @import("std");

const types = @import("types.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-n, --namespace <STR>   Namespace to get resources from.
        \\-A, --all-namespaces If present, list all objects across all namespaces. Specifing --namespace will be ignored.
        \\-s, --sort Prints the resources in order.
        \\-e, --exclude <STR>... Exclude crd types. Multiple can be excluded eg: "-e <CRD> -e <CRD>"
        \\-o, --output <OUTPUT> Changes the output format of the results.
        \\-d, --database <PATH> Path to the sqlite file to save the results. If the files does not exist it will be created.
        \\-l, --label <STR> Set the label that will be saved with entries when using the --database option.
        \\--log-level <LEVEL> Set the log level. All logs are saved to file.
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
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    var namespace: []const u8 = &[_]u8{};
    var allNamespaces = false;
    var sort = false;
    var output = types.Output.tty;
    var database: []const u8 = &[_]u8{};
    var label: []const u8 = &[_]u8{};
    var level = types.Level.info;

    if (res.args.help != 0)
        return clap.helpToFile(.stdout(), clap.Help, &params, .{});

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

    const config = types.Config{
        .namespace = namespace,
        .all = allNamespaces,
        .sort = sort,
        .output = output,
        .database = database,
        .label = label,
        .logLevel = level,
    };

    if (config.logLevel == .debug) {
        std.debug.print("Configuration:\n\tnamespace: {s}\n\tall namespaces: {}\n\tsort: {}\n\toutput: {s}\n\tbasebase: {s}\n\tlabel: {s}\n\tlog level: {s}\n", .{ config.namespace, config.all, config.sort, @tagName(config.output), config.database, config.label, @tagName(config.logLevel) });
    }

    var crdTypes = getCrdList(allocator) catch |err| switch (err) {
        error.BadExit => {
            std.debug.print("Kubectl returned a none zero exit code\n", .{});
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

    std.debug.print("Found {} lines:\n", .{crdTypes.items.len});
    for (crdTypes.items) |line| {
        std.debug.print("CRD type: {s}\n", .{line});
        const a = getCRJson(allocator, config, line) catch |err| switch (err) {
            error.NoData => {
                std.debug.print("No Data retruned for: {s}", .{line});
                continue;
            },
            else => return err,
        };
        std.debug.print("Kind: {s}\n", .{a.items[0].kind});
        for (a.items, 1..) |item, i| {
            std.debug.print("{d}: name = {s}, namespace = {s}\n", .{ i, item.metadata.name, item.metadata.namespace });
        }
        std.debug.print("\n", .{});
        defer {
            a.deinit(allocator);
        }
    }
}

fn getCRJson(allocator: std.mem.Allocator, config: types.Config, crd: []const u8) !types.ResourceList {
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

    std.debug.print("cmd: ", .{});
    for (cmd.items) |c| {
        std.debug.print("{s} ", .{c});
    }
    std.debug.print("\n", .{});
    const ownedCmd = try cmd.toOwnedSlice(allocator);
    defer allocator.free(ownedCmd);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = ownedCmd,
        .cwd = null,
        .env_map = null,
        .max_output_bytes = 1024 * 1024, // 1MB max output
    }) catch |err| {
        std.debug.print("Failed to run kubectl: {}\n", .{err});
        return err;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
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

    for (parsed.value.items) |item| {
        std.debug.print("item name: {s}\n", .{item.metadata.name});
    }
    std.debug.print("Number of items: {d}\n", .{parsed.value.items.len});

    return parsed.value.clone(allocator);
}

fn compareStrings(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn getCrdList(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    std.debug.print("somethig is done\n", .{});

    const cmd = [_][]const u8{ "kubectl", "api-resources", "--verbs=list", "--namespaced", "-o", "name" };
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &cmd,
        .cwd = null,
        .env_map = null,
        .max_output_bytes = 1024 * 1024, // 1MB max output
    }) catch |err| {
        std.debug.print("Failed to run kubectl: {}\n", .{err});
        return err;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.debug.print("stdout: {s}. stderr: {s}\n", .{ result.stdout, result.stdout });
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
