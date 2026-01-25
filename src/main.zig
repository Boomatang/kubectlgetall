const clap = @import("clap");
const std = @import("std");

const types = @import("types.zig");

var stdout_buf: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
const stdout: *std.io.Writer = &stdout_writer.interface;

pub const std_options: std.Options = .{
    // Keep compile-time logging permissive; runtime filter in `log`.
    .log_level = .debug,
    .logFn = log,
};

pub var log_level: std.log.Level = .info;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = comptime blk: {
        if (scope == .default)
            break :blk "[" ++ level.asText() ++ "] ";
        break :blk "[" ++ level.asText() ++ "][" ++ @tagName(scope) ++ "] ";
    };
    if (@intFromEnum(level) <= @intFromEnum(log_level)) {
        // Print the message to stderr, silently ignoring any errors
        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();
        const stderr = std.fs.File.stderr().deprecatedWriter();
        nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
    }
}

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
        \\--log-level <LEVEL> Set the log level. All logs are saved to file. Possible values are (debug, info, warn, error). Defualt level is warn.
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
    var level = types.Level.warn;

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
        .output = output,
        .database = database,
        .label = label,
        .logLevel = level,
    };

    std.log.debug("Configuration:\n\tnamespace: {s}\n\tall namespaces: {}\n\tsort: {}\n\toutput: {s}\n\tbasebase: {s}\n\tlabel: {s}\n\tlog level: {s}\n", .{ config.namespace, config.all, config.sort, @tagName(config.output), config.database, config.label, @tagName(config.logLevel) });

    var crdTypes = getCrdList(allocator) catch |err| switch (err) {
        error.BadExit => {
            std.log.err("Kubectl returned a none zero exit code\n", .{});
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

    std.log.info("Total number of CRD types found {}.\n", .{crdTypes.items.len});
    for (crdTypes.items) |line| {
        const a = getCRJson(allocator, config, line) catch |err| switch (err) {
            error.NoData => {
                continue;
            },
            else => return err,
        };
        defer {
            a.deinit(allocator);
        }
        try print_table(a);
    }

    const todo =
        \\To do after
        \\- get sort function to work.
        \\
    ;
    std.log.debug("{s}\n", .{todo});
}

fn print_table(data: types.ResourceList) !void {
    // TODO: This code is horrible, needs a large refactor
    const title_name = "NAME";
    const title_namespace = "NAMESPACE";
    const title_creationTimestamp = "CREATION TIMESTAMP";

    var max_name_length: usize = title_name.len;
    var max_namespace_length: usize = title_namespace.len;
    var max_creationTimestamp_length: usize = title_creationTimestamp.len;
    const kind = data.items[0].kind;
    for (data.items) |i| {
        if (i.metadata.name.len > max_name_length) max_name_length = i.metadata.name.len;
        if (i.metadata.namespace.len > max_namespace_length) max_namespace_length = i.metadata.namespace.len;
        if (i.metadata.creationTimestamp.len > max_creationTimestamp_length) max_creationTimestamp_length = i.metadata.creationTimestamp.len;
    }

    const headers: [3][]const u8 = .{ title_namespace, title_name, title_creationTimestamp };
    const spacing: [3]usize = .{ max_namespace_length, max_name_length, max_creationTimestamp_length };
    var spacing_required: usize = 0;
    for (spacing) |s| spacing_required += s;

    // add 2 for table ends
    // add 2 for each field printed (name, namespace) = 4
    // add field count - 1 for vertical divides
    // needs a - 1 for some reason
    const line_length = spacing_required + 2 + (2 * headers.len) + (headers.len - 1) - 1;
    var divider_idx: usize = 0;
    var divider = 2 + spacing[divider_idx] + 1;
    divider_idx += 1;

    const green_start = "\x1b[1;32m";
    const reset = "\x1b[0m";
    const top_left = "\u{250C}";
    const top_right = "\u{2510}";
    const bottom_left = "\u{2514}";
    const bottom_right = "\u{2518}";
    const horizontal = "\u{2500}";
    const top_junction = "\u{252C}";
    const bottom_junction = "\u{2534}";
    const intersection = "\u{253C}";
    const vertical = "\u{2502}";
    const left_junction = "\u{251C}";
    const right_junction = "\u{2524}";

    const padding = (line_length - kind.len) / 2;
    for (0..padding) |_| {
        try stdout.print(" ", .{});
    }
    try stdout.print("{s}{s}{s}\n", .{ green_start, kind, reset });
    // header line
    for (0..line_length + 1) |i| {
        if (i == 0) {
            try stdout.print("{s}", .{top_left});
        } else if (i == line_length) {
            try stdout.print("{s}\n", .{top_right});
        } else if (i == divider and divider_idx < spacing.len) {
            try stdout.print("{s}", .{top_junction});
            divider += spacing[divider_idx] + 3;
            divider_idx += 1;
        } else {
            try stdout.print("{s}", .{horizontal});
        }
    }

    divider_idx = 0;
    divider = 2 + spacing[divider_idx] + 1;
    divider_idx += 1;

    var pos: usize = 0;
    while (pos < line_length + 1) : (pos += 1) {
        if (pos == 0) {
            try stdout.print("{s}", .{vertical});
        } else if (pos == divider and divider_idx == headers.len) {
            try stdout.print("{s}\n", .{vertical});
            break;
        } else if (pos == 2) {
            try stdout.print("{s}", .{headers[0]});
            pos += headers[0].len - 1;
        } else if (pos == divider and divider_idx < headers.len) {
            try stdout.print("{s} {s}", .{ vertical, headers[divider_idx] });
            pos += headers[divider_idx].len - 1;
            divider += spacing[divider_idx] + 1;
            divider_idx += 1;
        } else {
            try stdout.print(" ", .{});
        }
    }

    divider_idx = 0;
    divider = 2 + spacing[divider_idx] + 1;
    divider_idx += 1;
    for (0..line_length + 1) |i| {
        if (i == 0) {
            try stdout.print("{s}", .{left_junction});
        } else if (i == line_length) {
            try stdout.print("{s}\n", .{right_junction});
        } else if (i == divider and divider_idx < spacing.len) {
            try stdout.print("{s}", .{intersection});
            divider += spacing[divider_idx] + 3;
            divider_idx += 1;
        } else {
            try stdout.print("{s}", .{horizontal});
        }
    }

    for (data.items, 1..) |item, idx| {
        divider_idx = 0;
        divider = 2 + spacing[divider_idx] + 1;
        divider_idx += 1;
        pos = 0;
        while (pos < line_length + 1) : (pos += 1) {
            if (pos == 0) {
                try stdout.print("{s}", .{vertical});
            } else if (pos == line_length) {
                try stdout.print("{s}\n", .{vertical});
            } else if (pos == 2) {
                try stdout.print("{s}", .{item.metadata.namespace});
                pos += item.metadata.namespace.len - 1;
            } else if (pos == divider) {
                if (divider_idx == 1) {
                    try stdout.print("{s} {s}", .{ vertical, item.metadata.name });
                    pos += item.metadata.name.len + 1;
                    divider += spacing[divider_idx] + 3;
                    divider_idx += 1;
                } else {
                    try stdout.print("{s} {s}", .{ vertical, item.metadata.creationTimestamp });
                    pos += item.metadata.creationTimestamp.len + 1;
                    divider += spacing[divider_idx];
                    divider_idx += 1;
                }
            } else {
                try stdout.print(" ", .{});
            }
        }

        divider_idx = 0;
        divider = 2 + spacing[divider_idx] + 1;
        divider_idx += 1;
        if (idx != data.items.len) {
            divider_idx = 0;
            divider = 2 + spacing[divider_idx] + 1;
            divider_idx += 1;
            for (0..line_length + 1) |i| {
                if (i == 0) {
                    try stdout.print("{s}", .{left_junction});
                } else if (i == line_length) {
                    try stdout.print("{s}\n", .{right_junction});
                } else if (i == divider and divider_idx < spacing.len) {
                    try stdout.print("{s}", .{intersection});
                    divider += spacing[divider_idx] + 3;
                    divider_idx += 1;
                } else {
                    try stdout.print("{s}", .{horizontal});
                }
            }
        } else {
            for (0..line_length + 1) |i| {
                if (i == 0) {
                    try stdout.print("{s}", .{bottom_left});
                } else if (i == line_length) {
                    try stdout.print("{s}\n\n", .{bottom_right});
                } else if (i == divider and divider_idx < spacing.len) {
                    try stdout.print("{s}", .{bottom_junction});
                    divider += spacing[divider_idx] + 3;
                    divider_idx += 1;
                } else {
                    try stdout.print("{s}", .{horizontal});
                }
            }
        }
    }
    try stdout.flush();
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

    const ownedCmd = try cmd.toOwnedSlice(allocator);
    defer allocator.free(ownedCmd);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = ownedCmd,
        .cwd = null,
        .env_map = null,
        .max_output_bytes = 1024 * 1024, // 1MB max output
    }) catch |err| {
        std.log.err("Failed to run kubectl: {}\n", .{err});
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

    return parsed.value.clone(allocator);
}

fn compareStrings(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn getCrdList(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    const cmd = [_][]const u8{ "kubectl", "api-resources", "--verbs=list", "--namespaced", "-o", "name" };
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &cmd,
        .cwd = null,
        .env_map = null,
        .max_output_bytes = 1024 * 1024, // 1MB max output
    }) catch |err| {
        std.log.err("Failed to run kubectl: {}\n", .{err});
        return err;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.log.debug("stdout: {s}. stderr: {s}\n", .{ result.stdout, result.stdout });
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
