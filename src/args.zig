const clap = @import("clap");
const types = @import("types.zig");

const SubCommands = enum {
    get,
    diff,
};

pub const main_parsers = .{
    .command = clap.parsers.enumeration(SubCommands),
    .LEVEL = clap.parsers.enumeration(types.Level),
};

pub const main_params = clap.parseParamsComptime(
    \\-h, --help Display tihs help and exit.
    \\--version Display version, and exit.
    \\--log-level <LEVEL> Set the log level. All logs are saved to file. Possible values are (debug, info, warn, error). Defualt level is warn.
    \\<command>
    \\
);

pub const MainArgs = clap.ResultEx(clap.Help, &main_params, main_parsers);
