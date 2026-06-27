const std = @import("std");
const sqlite = @import("sqlite");
const types = @import("types.zig");

var db: sqlite.Database = undefined;

pub fn init(database: []const u8) !void {
    std.log.debug("configure database: {s}", .{database});

    const c_string: [*:0]const u8 = @ptrCast(database);
    db = try sqlite.Database.open(.{
        .path = c_string,
    });
    try db.exec("CREATE TABLE IF NOT EXISTS results(id INTEGER PRIMARY KEY AUTOINCREMENT, apiVersion, kind, name, namespace, creationTimestamp, resourceVersion, generation, resultTimestamp, resultLabel)", .{});
}

pub fn added(allocator: std.mem.Allocator, config: types.DiffConfig) !types.ResourceList {
    std.log.debug("getting newer resource under label: {s}, compared to label: {s}", .{ config.label_b, config.label_a });
    return queryResources(allocator, added_sql, .{
        .label_a = sqlite.text(config.label_a),
        .label_b = sqlite.text(config.label_b),
    }, config.exclude);
}

pub fn updated(allocator: std.mem.Allocator, config: types.DiffConfig) !types.ResourceList {
    std.log.debug("getting updated resource under label: {s}, compared to label: {s}", .{ config.label_b, config.label_a });
    return queryResources(allocator, updated_sql, .{
        .label_a = sqlite.text(config.label_a),
        .label_b = sqlite.text(config.label_b),
    }, config.exclude);
}

pub fn deleted(allocator: std.mem.Allocator, config: types.DiffConfig) !types.ResourceList {
    std.log.debug("getting deleted resource under label: {s}, compared to label: {s}", .{ config.label_a, config.label_b });
    return queryResources(allocator, deleted_sql, .{
        .label_a = sqlite.text(config.label_a),
        .label_b = sqlite.text(config.label_b),
    }, config.exclude);
}

pub fn add(enties: types.ResourceList, label: ?[]const u8, timestamp: i64) !void {
    var _label: ?sqlite.Text = null;
    if (label) |l| _label = sqlite.text(l);

    const insert = try db.prepare(Entry, void, "INSERT INTO results VALUES (NULL, :apiVersion, :kind, :name, :namespace, :creationTimestamp, :resourceVersion, :generation, :resultTimestamp, :resultLabel)");
    defer insert.finalize();
    for (enties.items) |entry| {
        std.log.debug("adding {s}/{s}/{s} to database", .{
            entry.kind,
            entry.metadata.namespace,
            entry.metadata.name,
        });

        try insert.exec(.{
            .apiVersion = sqlite.text(entry.apiVersion),
            .kind = sqlite.text(entry.kind),
            .name = sqlite.text(entry.metadata.name),
            .namespace = sqlite.text(entry.metadata.namespace),
            .creationTimestamp = sqlite.text(entry.metadata.creationTimestamp),
            .resourceVersion = if (entry.metadata.resourceVersion) |rv| sqlite.text(rv) else sqlite.text(""),
            .generation = entry.metadata.generation,
            .resultTimestamp = timestamp,
            .resultLabel = _label,
        });
    }
}

const added_sql =
    \\SELECT apiVersion, kind, name, namespace, creationTimestamp, resourceVersion, generation
    \\FROM results r1
    \\WHERE r1.resultLabel = :label_b
    \\AND NOT EXISTS (
    \\    SELECT 1 FROM results r2
    \\    WHERE r2.resultLabel = :label_a
    \\    AND r2.name = r1.name AND r2.namespace = r1.namespace
    \\    AND r2.kind = r1.kind AND r2.apiVersion = r1.apiVersion
    \\)
    \\ORDER BY r1.kind, r1.name
;

const deleted_sql =
    \\SELECT apiVersion, kind, name, namespace, creationTimestamp, resourceVersion, generation
    \\FROM results r1
    \\WHERE r1.resultLabel = :label_a
    \\AND NOT EXISTS (
    \\    SELECT 1 FROM results r2
    \\    WHERE r2.resultLabel = :label_b
    \\    AND r2.name = r1.name AND r2.namespace = r1.namespace
    \\    AND r2.kind = r1.kind AND r2.apiVersion = r1.apiVersion
    \\)
    \\ORDER BY r1.kind, r1.name
;

const updated_sql =
    \\SELECT r2.apiVersion, r2.kind, r2.name, r2.namespace, r2.creationTimestamp, r2.resourceVersion, r2.generation
    \\FROM results r1
    \\JOIN results r2
    \\    ON r1.name = r2.name AND r1.namespace = r2.namespace
    \\    AND r1.kind = r2.kind AND r1.apiVersion = r2.apiVersion
    \\WHERE r1.resultLabel = :label_a AND r2.resultLabel = :label_b
    \\AND (r1.resourceVersion != r2.resourceVersion
    \\     OR (r1.resourceVersion = r2.resourceVersion AND r1.generation != r2.generation))
    \\ORDER BY r2.kind, r2.name
;

const DiffParams = struct {
    label_a: sqlite.Text,
    label_b: sqlite.Text,
};

const DiffRow = struct {
    apiVersion: sqlite.Text,
    kind: sqlite.Text,
    name: sqlite.Text,
    namespace: sqlite.Text,
    creationTimestamp: sqlite.Text,
    resourceVersion: sqlite.Text,
    generation: ?i64,
};

fn matchedExclude(haystack: ?[]const []const u8, needle: []const u8) ?[]const u8 {
    if (haystack) |stack| {
        for (stack) |s| {
            if (std.ascii.eqlIgnoreCase(s, needle)) return s;
        }
    }
    return null;
}

fn queryResources(allocator: std.mem.Allocator, comptime sql: []const u8, params: DiffParams, exclude: ?[]const []const u8) !types.ResourceList {
    const stmt = try db.prepare(DiffParams, DiffRow, sql);
    defer stmt.finalize();

    try stmt.bind(params);

    var items: std.ArrayList(types.Resource) = .empty;
    errdefer {
        for (items.items) |item| item.deinit(allocator);
        items.deinit(allocator);
    }

    while (try stmt.step()) |row| {
        if (matchedExclude(exclude, row.kind.data)) |matched| {
            std.log.debug("excluding {s}/{s} matched by -e {s}", .{ row.apiVersion.data, row.kind.data, matched });
            continue;
        }
        const resource = types.Resource{
            .kind = try allocator.dupe(u8, row.kind.data),
            .apiVersion = try allocator.dupe(u8, row.apiVersion.data),
            .metadata = .{
                .name = try allocator.dupe(u8, row.name.data),
                .namespace = try allocator.dupe(u8, row.namespace.data),
                .creationTimestamp = try allocator.dupe(u8, row.creationTimestamp.data),
                .resourceVersion = if (row.resourceVersion.data.len > 0) try allocator.dupe(u8, row.resourceVersion.data) else null,
                .generation = if (row.generation) |g| @as(u64, @intCast(g)) else null,
            },
        };
        try items.append(allocator, resource);
    }

    return types.ResourceList{ .items = try items.toOwnedSlice(allocator) };
}

const Entry = struct {
    apiVersion: sqlite.Text,
    kind: sqlite.Text,
    name: sqlite.Text,
    namespace: sqlite.Text,
    creationTimestamp: sqlite.Text,
    resourceVersion: sqlite.Text,
    generation: ?u64,
    resultTimestamp: i64,
    resultLabel: ?sqlite.Text,
};
