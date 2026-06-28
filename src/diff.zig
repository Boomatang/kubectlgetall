const std = @import("std");
const clap = @import("clap");
const logging = @import("log.zig");
const db = @import("database.zig");
const table = @import("table.zig");
const types = @import("types.zig");
const help = @import("help.zig");
const args = @import("args.zig");

pub fn diffMain(io: std.Io, gpa: std.mem.Allocator, iter: *std.process.Args.Iterator) !void {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &args.diff_params, args.diff_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try help.diff(io, .stdout());
        std.process.exit(0);
    }

    if (res.args.@"log-level") |l| {
        logging.setLogLevel(l);
    }

    const config = types.DiffConfig{
        .database = res.args.database orelse return error.MissingDatabase,
        .label_a = res.positionals[0] orelse return error.MissingArg1,
        .label_b = res.positionals[1] orelse return error.MissingArg2,
        .output = res.args.output orelse .tty,
        .exclude = if (res.args.exclude.len > 0) res.args.exclude else null,
    };
    std.log.debug("{f}", .{config});

    try db.init(config.database);

    const added_resources = try db.added(gpa, config);
    defer added_resources.deinit(gpa);
    const updated_resources = try db.updated(gpa, config);
    defer updated_resources.deinit(gpa);
    const deleted_resources = try db.deleted(gpa, config);
    defer deleted_resources.deinit(gpa);

    switch (config.output) {
        .tty => {
            const max_width = maxTableWidth(added_resources, updated_resources, deleted_resources);
            try printSection(io, "Added Resources", added_resources, max_width);
            try printSection(io, "Updated Resources", updated_resources, max_width);
            try printSection(io, "Removed Resources", deleted_resources, max_width);
        },
        .json => {
            try printJson(io, gpa, added_resources, updated_resources, deleted_resources);
        },
        .sqlite => {
            std.log.err("sqlite output is not supported for diff", .{});
            std.process.exit(1);
        },
    }
}

fn printJson(io: std.Io, gpa: std.mem.Allocator, added: types.ResourceList, updated: types.ResourceList, deleted: types.ResourceList) !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(io, &buf);
    const stdout = &file_writer.interface;

    try stdout.print("{{\"added\": ", .{});
    try printResourceListJson(stdout, gpa, added);
    try stdout.print(", \"updated\": ", .{});
    try printResourceListJson(stdout, gpa, updated);
    try stdout.print(", \"deleted\": ", .{});
    try printResourceListJson(stdout, gpa, deleted);
    try stdout.print("}}\n", .{});
    try stdout.flush();
}

fn printResourceListJson(stdout: *std.Io.Writer, gpa: std.mem.Allocator, resources: types.ResourceList) !void {
    if (resources.items.len == 0) {
        try stdout.print("[]", .{});
        return;
    }
    try stdout.print("[", .{});
    for (resources.items, 0..) |item, i| {
        const text = try item.toJson(gpa);
        defer gpa.free(text);
        try stdout.print("{s}", .{text});
        if (i < resources.items.len - 1) {
            try stdout.print(",", .{});
        }
    }
    try stdout.print("]", .{});
}

fn maxTableWidth(added: types.ResourceList, updated: types.ResourceList, deleted: types.ResourceList) usize {
    var max: usize = 40;
    if (added.items.len > 0) max = @max(max, table.calcWidth(added));
    if (updated.items.len > 0) max = @max(max, table.calcWidth(updated));
    if (deleted.items.len > 0) max = @max(max, table.calcWidth(deleted));
    return max;
}

fn printSection(io: std.Io, header: []const u8, resources: types.ResourceList, width: usize) !void {
    if (resources.items.len == 0) {
        std.log.debug("{s}: no resources found, skipping.", .{header});
        return;
    }
    try section(io, header, width);
    try printByKind(io, resources);
}

fn printByKind(io: std.Io, resources: types.ResourceList) !void {
    if (resources.items.len == 0) {
        std.log.debug("Resource list is empty, early exit.", .{});
        return;
    }

    var start: usize = 0;
    while (start < resources.items.len) {
        const kind = resources.items[start].kind;
        var end = start + 1;
        while (end < resources.items.len and std.mem.eql(u8, resources.items[end].kind, kind)) {
            end += 1;
        }
        try table.print(io, .{ .items = resources.items[start..end] });
        start = end;
    }
}

fn section(io: std.Io, header: []const u8, width: usize) !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(io, &buf);
    const stdout = &file_writer.interface;

    const color_start = "\x1b[1;33m";
    const reset = "\x1b[0m";
    const padding = (width - header.len) / 2;

    try stdout.print("\n{s}", .{color_start});
    for (0..width) |_| try stdout.print("=", .{});
    try stdout.print("\n", .{});
    for (0..padding) |_| try stdout.print(" ", .{});
    try stdout.print("{s}\n", .{header});
    for (0..width) |_| try stdout.print("=", .{});
    try stdout.print("{s}\n\n", .{reset});
    try stdout.flush();
}
