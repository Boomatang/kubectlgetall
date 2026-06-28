const std = @import("std");

const types = @import("types.zig");

pub fn getCrdList(io: std.Io, gpa: std.mem.Allocator) !std.ArrayList([]const u8) {
    const cmd = [_][]const u8{ "kubectl", "api-resources", "--verbs=list", "--namespaced", "-o", "name" };
    const result = std.process.run(gpa, io, .{
        .argv = &cmd,
    }) catch |err| {
        std.log.err("Failed to run kubectl: {}", .{err});
        return err;
    };
    defer {
        gpa.free(result.stdout);
        gpa.free(result.stderr);
    }

    if (result.term.exited != 0) {
        std.log.debug("stdout: {s}. stderr: {s}", .{ result.stdout, result.stderr });
        return error.BadExit;
    }
    var lines: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (lines.items) |item| {
            gpa.free(item);
        }
        lines.deinit(gpa);
    }

    var iter = std.mem.splitScalar(u8, result.stdout, '\n');
    while (iter.next()) |line| {
        if (line.len > 0) {
            const owned = try gpa.dupe(u8, line);
            errdefer gpa.free(owned);
            try lines.append(gpa, owned);
        }
    }

    return lines;
}

pub fn getCRJson(io: std.Io, gpa: std.mem.Allocator, config: anytype, crd: []const u8) !types.ResourceList {
    const T = @TypeOf(config);
    comptime {
        if (!@hasField(T, "all")) @compileError("config type must have an 'all' field");
        if (!@hasField(T, "namespace")) @compileError("config type must have a 'namespace' field");
    }

    const initialcmd = &[_][]const u8{ "kubectl", "get", "--ignore-not-found", crd, "--output", "json" };

    var cmd: std.ArrayList([]const u8) = .empty;
    defer cmd.deinit(gpa);

    try cmd.appendSlice(gpa, initialcmd);
    if (config.all) {
        try cmd.append(gpa, "--all-namespaces");
    } else {
        try cmd.append(gpa, "--namespace");
        try cmd.append(gpa, config.namespace);
    }

    const ownedCmd = try cmd.toOwnedSlice(gpa);
    defer gpa.free(ownedCmd);

    const result = std.process.run(gpa, io, .{
        .argv = ownedCmd,
    }) catch |err| {
        std.log.err("Failed to run kubectl: {}", .{err});
        return err;
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    if (result.term.exited != 0) {
        return error.BadExit;
    }

    if (result.stdout.len == 0) {
        return error.NoData;
    }

    const parsed: std.json.Parsed(types.ResourceList) = std.json.parseFromSlice(types.ResourceList, gpa, result.stdout, .{ .ignore_unknown_fields = true }) catch |err| switch (err) {
        std.json.ParseFromValueError.MissingField => return error.NotFound,
        else => return err,
    };

    defer {
        parsed.deinit();
    }

    return parsed.value.clone(gpa);
}
