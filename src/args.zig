const clap = @import("clap");
const logging = @import("log.zig");
const types = @import("types.zig");

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
