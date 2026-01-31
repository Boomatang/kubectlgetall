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
    try db.exec("CREATE TABLE IF NOT EXISTS results(id INTEGER PRIMARY KEY AUTOINCREMENT, apiVersion, kind, name, namespace, creationTimestamp, resourceVersion, resultTimestamp, resultLabel)", .{});
}

pub fn add(enties: types.ResourceList, label: ?[]const u8, timestamp: i64) !void {
    var _label: ?sqlite.Text = null;
    if (label) |l| _label = sqlite.text(l);

    const insert = try db.prepare(Entry, void, "INSERT INTO results VALUES (NULL, :apiVersion, :kind, :name, :namespace, :creationTimestamp, :resourceVersion, :resultTimestamp, :resultLabel)");
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
            .resourceVersion = sqlite.text(entry.metadata.resourceVersion.?),
            .resultTimestamp = timestamp,
            .resultLabel = _label,
        });
    }
}

const Entry = struct {
    apiVersion: sqlite.Text,
    kind: sqlite.Text,
    name: sqlite.Text,
    namespace: sqlite.Text,
    creationTimestamp: sqlite.Text,
    resourceVersion: sqlite.Text,
    resultTimestamp: i64,
    resultLabel: ?sqlite.Text,
};
