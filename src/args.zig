const std = @import("std");
const clap = @import("clap");
const logging = @import("log.zig");
const types = @import("types.zig");

const SubCommands = enum {
    get,
    diff,
    snapshot,
};

pub const main_parsers = .{
    .command = clap.parsers.enumeration(SubCommands),
    .LEVEL = clap.parsers.enumeration(logging.Level),
};

pub const main_params = clap.parseParamsComptime(
    \\-h, --help Display this help and exit.
    \\--version Display version, and exit.
    \\--log-level <LEVEL> Set the log level. All logs are saved to file. Possible values are (debug, info, warn, error). Default level is warn.
    \\<command>
    \\
);

pub const get_parsers = .{
    .OUTPUT = clap.parsers.enumeration(types.Output),
    .STR = clap.parsers.string,
    .PATH = clap.parsers.string,
    .LEVEL = clap.parsers.enumeration(logging.Level),
};

pub const get_params = clap.parseParamsComptime(
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

pub const diff_parsers = .{
    .PATH = clap.parsers.string,
    .STR = clap.parsers.string,
    .LABEL = clap.parsers.string,
    .LEVEL = clap.parsers.enumeration(logging.Level),
    .OUTPUT = clap.parsers.enumeration(types.Output),
};

pub const diff_params = clap.parseParamsComptime(
    \\-h, --help Display this help and exit.
    \\-d, --database <PATH> Path to SQLite database to load data from.
    \\-e, --exclude <STR>... Exclude resource types. Multiple can be excluded eg: "-e <KIND> -e <KIND>"
    \\-o, --output <OUTPUT> Changes the output format of the results. [default: tty, tty|json]
    \\--log-level <LEVEL> Set the log level. All logs are saved to file. Possible values are (debug, info, warn, error). Default level is warn.
    \\<LABEL> Older label used.
    \\<LABEL> Newer label used.
    \\
);

pub const snapshot_parsers = .{
    .PATH = clap.parsers.string,
    .STR = clap.parsers.string,
    .LABEL = clap.parsers.string,
    .LEVEL = clap.parsers.enumeration(logging.Level),
    .TIME = parseDuration,
    .INT = clap.parsers.int(u32, 10),
};

pub const DurationError = error{
    InvalidDurationFormat,
    Overflow,
    InvalidCharacter,
};

fn parseDuration(in: []const u8) DurationError!u64 {
    if (in.len == 0) return error.InvalidDurationFormat;

    const last = in[in.len - 1];
    const multiplier: u64, const digits: []const u8 = switch (last) {
        's' => .{ 1, in[0 .. in.len - 1] },
        'm' => .{ 60, in[0 .. in.len - 1] },
        'h' => .{ 3600, in[0 .. in.len - 1] },
        '0'...'9' => .{ 1, in },
        else => return error.InvalidDurationFormat,
    };

    if (digits.len == 0) return error.InvalidDurationFormat;

    const value = std.fmt.parseUnsigned(u64, digits, 10) catch |err| switch (err) {
        error.Overflow => return error.Overflow,
        error.InvalidCharacter => return error.InvalidCharacter,
    };

    return std.math.mul(u64, value, multiplier) catch return error.Overflow;
}

pub const snapshot_params = clap.parseParamsComptime(
    \\-h, --help Display this help and exit.
    \\-n, --namespace <STR> Namespace to get resources from.
    \\-A, --all-namespaces If present, list all objects across all namespaces. Specifying --namespace will be ignored.
    \\-d, --database <PATH> Path to the sqlite file to save the results. If the files does not exist it will be created. [REQUIRED]
    \\-l, --label <STR> Set the label that will be saved with entries when using the --database option. [REQUIRED]
    \\--delay <TIME> Time delay between snaphotting the cluster. Format can be INT, or INTs, INTm, INTh. Default time delay of 60, 60s, 1m.
    \\-c, --count <INT> Number of snapshots to take. Default 0, meaning unlimited.
    \\--limit <TIME> Max runtime of snapshot. If time limit is reached before the count limit is reached the application will exit. Format can be INT, or INTs, INTm, INTh. Default of time limit of 0, meaning unlimited.
    \\--log-level <LEVEL> Set the log level. All logs are saved to file. Possible values are (debug, info, warn, error). Default level is warn.
    \\-e, --exclude <STR>... Exclude resource types. Multiple can be excluded eg: "-e <KIND> -e <KIND>"
    \\
);
