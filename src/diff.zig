const std = @import("std");
const args = @import("args.zig");
const clap = @import("clap");
const logging = @import("log.zig");
const types = @import("types.zig");

pub fn diffMain(io: std.Io, gpa: std.mem.Allocator, iter: *std.process.Args.Iterator, main_args: args.MainArgs) !void {
    _ = main_args;

    const params = comptime clap.parseParamsComptime(
        \\-h, --help Display this help and exit.
        \\-d, --database <PATH> Path to SQLite database to load data from.
        \\--log-level <LEVEL> Set the log level. All logs are saved to file. Possible values are (debug, info, warn, error). Defualt level is warn.
        \\<LABEL> Older label used.
        \\<LABEL> Newer label used.
        \\
    );

    const parsers = comptime .{
        .PATH = clap.parsers.string,
        .LABEL = clap.parsers.string,
        .LEVEL = clap.parsers.enumeration(logging.Level),
    };

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

    if (res.args.help != 0)
        return clap.helpToFile(io, .stdout(), clap.Help, &params, .{});

    if (res.args.@"log-level") |l| {
        logging.setLogLevel(l);
    }

    const database = res.args.database orelse return error.MissingDatabase;
    const label_a = res.positionals[0] orelse return error.MissingArg1;
    const label_b = res.positionals[1] orelse return error.MissingArg2;

    std.debug.print("running diff\ndatabase: {s}\nlabel A: {s}\nlabel B: {s}\n", .{ database, label_a, label_b });
}
