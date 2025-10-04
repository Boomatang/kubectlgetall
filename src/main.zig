const clap = @import("clap");
const std = @import("std");

const Config = struct {
    namespace: []const u8,
    all: bool,
    sort: bool,
    exclude: ?[][]const u8 = null, //TODO: need to pull these from the args.
    output: Output,
    database: []const u8,
    label: []const u8,
    logLevel: Level,
};

const Output = enum { tty, json, sqlite };
const Level = enum { info, debug };
const Bool = enum { true, false };

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-n, --namespace <STR>   Namespace to get resources from.
        \\-A, --all-namespaces <BOOL> If present, list all objects across all namespaces. Specifing --namespace will be ignored.
        \\-s, --sort <BOOL> Prints the resources in order.
        \\-e, --exclude <STR>... Exclude crd types. Multiple can be excluded eg: "-e <CRD> -e <CRD>"
        \\-o, --output <OUTPUT> Changes the output format of the results.
        \\-d, --database <PATH> Path to the sqlite file to save the results. If the files does not exist it will be created.
        \\-l, --label <STR> Set the label that will be saved with entries when using the --database option.
        \\--log-level <LEVEL> Set the log level. All logs are saved to file.
        \\
    );

    const parsers = comptime .{
        .OUTPUT = clap.parsers.enumeration(Output),
        .STR = clap.parsers.string,
        .PATH = clap.parsers.string,
        .LEVEL = clap.parsers.enumeration(Level),
        .BOOL = clap.parsers.enumeration(Bool),
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
    var output = Output.tty;
    var database: []const u8 = &[_]u8{};
    var label: []const u8 = &[_]u8{};
    var level = Level.info;

    if (res.args.help != 0)
        return clap.helpToFile(.stdout(), clap.Help, &params, .{});

    if (res.args.namespace) |n| {
        namespace = n;
    }

    if (res.args.@"all-namespaces") |n| {
        if (n == Bool.true) {
            allNamespaces = true;
        }
    }

    if (res.args.sort) |s| {
        if (s == Bool.true) {
            sort = true;
        }
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

    const config = Config{
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
}
