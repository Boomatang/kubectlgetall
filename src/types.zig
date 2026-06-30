const std = @import("std");

pub const Output = enum { tty, json, sqlite };
pub const Bool = enum { true, false };

pub const DefaultDelay: i64 = 60;

pub const Config = struct {
    namespace: []const u8,
    all: bool,
    sort: bool,
    exclude: ?[]const []const u8 = null,
    output: Output,
    database: []const u8,
    label: []const u8,
    timestamp: i64,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            "Configuration:\n\tnamespace: {s}\n\tall namespaces: {}\n\tsort: {}\n\texclude: ",
            .{ self.namespace, self.all, self.sort },
        );

        if (self.exclude) |items| {
            try writer.writeAll("[");
            for (items, 0..) |item, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}", .{item});
            }
            try writer.writeAll("]\n");
        } else {
            try writer.writeAll("null\n");
        }

        try writer.print(
            "\toutput: {s}\n\tdatabase: {s}\n\tlabel: {s}",
            .{ @tagName(self.output), self.database, self.label },
        );

        try writer.flush();
    }
};

pub const DiffConfig = struct {
    database: []const u8,
    label_a: []const u8,
    label_b: []const u8,
    output: Output,
    exclude: ?[]const []const u8 = null,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            "Configuration:\n\tdatabase: {s}\n\tlabel A: {s}\n\tlabel B: {s}\n\toutput: {s}\n\texclude: ",
            .{ self.database, self.label_a, self.label_b, @tagName(self.output) },
        );

        if (self.exclude) |items| {
            try writer.writeAll("[");
            for (items, 0..) |item, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}", .{item});
            }
            try writer.writeAll("]\n");
        } else {
            try writer.writeAll("null\n");
        }

        try writer.flush();
    }
};

pub const SnapshotConfig = struct {
    database: []const u8,
    label: []const u8,
    exclude: ?[]const []const u8 = null,
    count: u64 = 0,
    limit: i64 = 0,
    delay: i64 = DefaultDelay,
    namespace: []const u8,
    all: bool,
    startTime: i64,
    interation: usize = 0,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            "Configuration:\n\tnamespace: {s}\n\tall namespaces: {}\n\tdatabase: {s}\n\tlabel: {s}\n\tstart time: {}\n\tcount: {}\n\tlimit: {}\n\tdelay: {}\n\tinteration: {}\n\texclude: ",
            .{
                self.namespace,
                self.all,
                self.database,
                self.label,
                self.startTime,
                self.count,
                self.limit,
                self.delay,
                self.interation,
            },
        );

        if (self.exclude) |items| {
            try writer.writeAll("[");
            for (items, 0..) |item, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}", .{item});
            }
            try writer.writeAll("]\n");
        } else {
            try writer.writeAll("null\n");
        }

        try writer.flush();
    }
};

pub const Metadata = struct {
    name: []const u8,
    namespace: []const u8,
    creationTimestamp: []const u8,
    resourceVersion: ?[]const u8 = null,
    generation: ?u64 = null,

    pub fn clone(self: @This(), gpa: std.mem.Allocator) !Metadata {
        return .{
            .name = try gpa.dupe(u8, self.name),
            .namespace = try gpa.dupe(u8, self.namespace),
            .creationTimestamp = try gpa.dupe(u8, self.creationTimestamp),
            .resourceVersion = if (self.resourceVersion) |r| try gpa.dupe(u8, r) else null,
            .generation = self.generation,
        };
    }

    pub fn deinit(self: @This(), gpa: std.mem.Allocator) void {
        gpa.free(self.namespace);
        gpa.free(self.name);
        gpa.free(self.creationTimestamp);
        if (self.resourceVersion) |r| gpa.free(r);
    }
};

pub const Resource = struct {
    kind: []const u8,
    apiVersion: []const u8,
    metadata: Metadata,

    pub fn toJson(self: @This(), gpa: std.mem.Allocator) ![]const u8 {
        var buffer = try std.ArrayList(u8).initCapacity(gpa, 256);
        defer buffer.deinit(gpa);

        const initial_string = try std.fmt.allocPrint(gpa, "{{\"kind\": \"{s}\", \"apiVersion\": \"{s}\", \"name\": \"{s}\", \"namespace\": \"{s}\", \"creationTimestamp\": \"{s}\"", .{
            self.kind,
            self.apiVersion,
            self.metadata.name,
            self.metadata.namespace,
            self.metadata.creationTimestamp,
        });
        try buffer.appendSlice(gpa, initial_string);
        defer gpa.free(initial_string);

        if (self.metadata.resourceVersion) |version| {
            const resource_version = try std.fmt.allocPrint(gpa, ", \"resourceVersion\": \"{s}\"", .{version});
            defer gpa.free(resource_version);
            try buffer.appendSlice(gpa, resource_version);
        }

        if (self.metadata.generation) |generation| {
            const generation_str = try std.fmt.allocPrint(gpa, ", \"generation\": {}", .{generation});
            defer gpa.free(generation_str);
            try buffer.appendSlice(gpa, generation_str);
        }

        try buffer.append(gpa, '}');

        return try gpa.dupe(u8, buffer.items);
    }

    pub fn clone(self: @This(), allocator: std.mem.Allocator) !Resource {
        return .{
            .kind = try allocator.dupe(u8, self.kind),
            .apiVersion = try allocator.dupe(u8, self.apiVersion),
            .metadata = try self.metadata.clone(allocator),
        };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.apiVersion);
        allocator.free(self.kind);
        self.metadata.deinit(allocator);
    }
};

pub const ResourceList = struct {
    items: []Resource,

    pub fn toJson(self: @This(), gpa: std.mem.Allocator) ![]const u8 {
        var buffer = try std.ArrayList(u8).initCapacity(gpa, 256);
        defer buffer.deinit(gpa);

        try buffer.append(gpa, '[');
        for (self.items, 0..) |item, i| {
            const text = try item.toJson(gpa);
            defer gpa.free(text);

            try buffer.appendSlice(gpa, text);
            if (i < self.items.len - 1) {
                try buffer.append(gpa, ',');
            }
        }
        try buffer.append(gpa, ']');

        return try gpa.dupe(u8, buffer.items);
    }

    pub fn clone(self: @This(), gpa: std.mem.Allocator) !ResourceList {
        var new_items = try gpa.alloc(Resource, self.items.len);

        // On error, deinit any items that were already initialized and free the array.
        var initialized: usize = 0;
        errdefer {
            // deinitialize only the items that were constructed so far
            for (new_items[0..initialized]) |it| it.deinit(gpa);
            gpa.free(new_items);
        }

        // Clone each item; increment `initialized` after a successful clone.
        for (self.items, 0..) |item, i| {
            new_items[i] = try item.clone(gpa);
            initialized += 1;
        }

        // Success: cancel the errdefer cleanup by returning normally.
        return ResourceList{ .items = new_items };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        for (self.items) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.items);
    }
};
