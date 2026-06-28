const clap = @import("clap");
const std = @import("std");
const build_options = @import("build_options");

const db = @import("database.zig");
const types = @import("types.zig");
const table = @import("table.zig");
const arg = @import("args.zig");
const diff = @import("diff.zig");
const get = @import("get.zig");
const logging = @import("log.zig");
const help = @import("help.zig");
const snapshot = @import("snapshot.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logging.log,
};

pub fn main(init: std.process.Init) !void {
    var iter = try init.minimal.args.iterateAllocator(init.gpa);
    defer iter.deinit();

    _ = iter.next();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &arg.main_params, arg.main_parsers, &iter, .{
        .allocator = init.gpa,
        .diagnostic = &diag,
        .terminating_positional = 0,
    }) catch |err| {
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try help.main(init.io, .stdout());
        std.process.exit(0);
    }

    if (res.args.version != 0) {
        const version = try std.fmt.allocPrint(init.gpa, "{s}, {s}\n", .{ build_options.name, build_options.version });
        defer init.gpa.free(version);
        var buf: [1024]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        try writer.interface.writeAll(version);
        try writer.interface.flush();
        std.process.exit(0);
    }

    if (res.args.@"log-level") |l| {
        logging.setLogLevel(l);
    }

    const command = res.positionals[0] orelse {
        try help.main(init.io, .stdout());
        return error.MissingCommand;
    };
    switch (command) {
        .get => try get.getMain(init.io, init.gpa, &iter),
        .diff => try diff.diffMain(init.io, init.gpa, &iter),
        .snapshot => try snapshot.cmd(init.io, init.gpa, &iter),
    }
}
