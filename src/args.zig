const clap = @import("clap");
const logging = @import("log.zig");

const SubCommands = enum {
    get,
    diff,
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
