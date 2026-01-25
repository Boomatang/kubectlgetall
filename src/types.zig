const std = @import("std");

pub const Output = enum { tty, json, sqlite };
pub const Level = enum { info, debug, @"error", warn };
pub const Bool = enum { true, false };

pub const Config = struct {
    namespace: []const u8,
    all: bool,
    sort: bool,
    exclude: ?[][]const u8 = null, //TODO: need to pull these from the args.
    output: Output,
    database: []const u8,
    label: []const u8,
    logLevel: Level,
};

pub const Metadata = struct {
    name: []const u8,
    namespace: []const u8,
    creationTimestamp: []const u8,
    resourceVersion: ?[]const u8,

    pub fn clone(self: Metadata, allocator: std.mem.Allocator) !Metadata {
        return .{
            .name = try allocator.dupe(u8, self.name),
            .namespace = try allocator.dupe(u8, self.namespace),
            .creationTimestamp = try allocator.dupe(u8, self.creationTimestamp),
            .resourceVersion = if (self.resourceVersion) |r|
                try allocator.dupe(u8, r)
            else
                null,
        };
    }

    pub fn deinit(self: Metadata, allocator: std.mem.Allocator) void {
        allocator.free(self.namespace);
        allocator.free(self.name);
        allocator.free(self.creationTimestamp);
        if (self.resourceVersion) |r| allocator.free(r);
    }
};

pub const Resource = struct {
    kind: []const u8,
    apiVersion: []const u8,
    metadata: Metadata,

    pub fn clone(self: Resource, allocator: std.mem.Allocator) !Resource {
        return .{
            .kind = try allocator.dupe(u8, self.kind),
            .apiVersion = try allocator.dupe(u8, self.apiVersion),
            .metadata = try self.metadata.clone(allocator),
        };
    }

    pub fn deinit(self: Resource, allocator: std.mem.Allocator) void {
        allocator.free(self.apiVersion);
        allocator.free(self.kind);
        self.metadata.deinit(allocator);
    }
};

pub const ResourceList = struct {
    items: []Resource,

    pub fn clone(self: ResourceList, allocator: std.mem.Allocator) !ResourceList {
        var new_items = try allocator.alloc(Resource, self.items.len);

        // On error, deinit any items that were already initialized and free the array.
        var initialized: usize = 0;
        errdefer {
            // deinitialize only the items that were constructed so far
            for (new_items[0..initialized]) |it| it.deinit(allocator);
            allocator.free(new_items);
        }

        // Clone each item; increment `initialized` after a successful clone.
        for (self.items, 0..) |item, i| {
            new_items[i] = try item.clone(allocator);
            initialized += 1;
        }

        // Success: cancel the errdefer cleanup by returning normally.
        return ResourceList{ .items = new_items };
    }

    pub fn deinit(self: ResourceList, allocator: std.mem.Allocator) void {
        for (self.items) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.items);
    }
};
