const std = @import("std");

pub fn matchedExclude(haystack: ?[]const []const u8, needle: []const u8) ?[]const u8 {
    if (haystack) |stack| {
        for (stack) |s| {
            if (std.ascii.eqlIgnoreCase(s, needle)) return s;
        }
    }
    return null;
}

test "null haystack returns null" {
    try std.testing.expectEqual(null, matchedExclude(null, "Pod"));
}

test "no match returns null" {
    const haystack = &[_][]const u8{ "Service", "Deployment" };
    try std.testing.expectEqual(null, matchedExclude(haystack, "ConfigMap"));
}

test "exact match returns matched string" {
    const haystack = &[_][]const u8{ "Secret", "Ingress", "Pod" };
    try std.testing.expectEqualStrings("Ingress", matchedExclude(haystack, "Ingress").?);
}

test "case-insensitive match" {
    const haystack = &[_][]const u8{ "deployment", "ReplicaSet" };
    try std.testing.expectEqualStrings("ReplicaSet", matchedExclude(haystack, "replicaset").?);
    try std.testing.expectEqualStrings("deployment", matchedExclude(haystack, "DEPLOYMENT").?);
}

test "different length strings do not match" {
    const haystack = &[_][]const u8{ "services", "Pod" };
    try std.testing.expectEqual(null, matchedExclude(haystack, "service"));
    try std.testing.expectEqual(null, matchedExclude(haystack, "Pods"));
}

test "returns first match when multiple could match" {
    const haystack = &[_][]const u8{ "node", "NODE", "Node" };
    try std.testing.expectEqualStrings("node", matchedExclude(haystack, "Node").?);
}
