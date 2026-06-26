const std = @import("std");
const types = @import("types.zig");

pub fn print(io: std.Io, data: types.ResourceList) !void {
    // TODO: This code is horrible, needs a large refactor

    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(io, &buf);
    const stdout = &file_writer.interface;
    const title_name = "NAME";
    const title_namespace = "NAMESPACE";
    const title_creationTimestamp = "CREATION TIMESTAMP";

    var max_name_length: usize = title_name.len;
    var max_namespace_length: usize = title_namespace.len;
    var max_creationTimestamp_length: usize = title_creationTimestamp.len;
    const kind = data.items[0].kind;
    for (data.items) |i| {
        if (i.metadata.name.len > max_name_length) max_name_length = i.metadata.name.len;
        if (i.metadata.namespace.len > max_namespace_length) max_namespace_length = i.metadata.namespace.len;
        if (i.metadata.creationTimestamp.len > max_creationTimestamp_length) max_creationTimestamp_length = i.metadata.creationTimestamp.len;
    }

    const headers: [3][]const u8 = .{ title_namespace, title_name, title_creationTimestamp };
    const spacing: [3]usize = .{ max_namespace_length, max_name_length, max_creationTimestamp_length };
    var spacing_required: usize = 0;
    for (spacing) |s| spacing_required += s;

    // add 2 for table ends
    // add 2 for each field printed (name, namespace) = 4
    // add field count - 1 for vertical divides
    // needs a - 1 for some reason
    const line_length = spacing_required + 2 + (2 * headers.len) + (headers.len - 1) - 1;
    var divider_idx: usize = 0;
    var divider = 2 + spacing[divider_idx] + 1;
    divider_idx += 1;

    const green_start = "\x1b[1;32m";
    const reset = "\x1b[0m";
    const top_left = "\u{250C}";
    const top_right = "\u{2510}";
    const bottom_left = "\u{2514}";
    const bottom_right = "\u{2518}";
    const horizontal = "\u{2500}";
    const top_junction = "\u{252C}";
    const bottom_junction = "\u{2534}";
    const intersection = "\u{253C}";
    const vertical = "\u{2502}";
    const left_junction = "\u{251C}";
    const right_junction = "\u{2524}";

    const padding = (line_length - kind.len) / 2;
    for (0..padding) |_| {
        try stdout.print(" ", .{});
    }
    try stdout.print("{s}{s}{s}\n", .{ green_start, kind, reset });
    // header line
    for (0..line_length + 1) |i| {
        if (i == 0) {
            try stdout.print("{s}", .{top_left});
        } else if (i == line_length) {
            try stdout.print("{s}\n", .{top_right});
        } else if (i == divider and divider_idx < spacing.len) {
            try stdout.print("{s}", .{top_junction});
            divider += spacing[divider_idx] + 3;
            divider_idx += 1;
        } else {
            try stdout.print("{s}", .{horizontal});
        }
    }

    divider_idx = 0;
    divider = 2 + spacing[divider_idx] + 1;
    divider_idx += 1;

    var pos: usize = 0;
    while (pos < line_length + 1) : (pos += 1) {
        if (pos == 0) {
            try stdout.print("{s}", .{vertical});
        } else if (pos == divider and divider_idx == headers.len) {
            try stdout.print("{s}\n", .{vertical});
            break;
        } else if (pos == 2) {
            try stdout.print("{s}", .{headers[0]});
            pos += headers[0].len - 1;
        } else if (pos == divider and divider_idx < headers.len) {
            try stdout.print("{s} {s}", .{ vertical, headers[divider_idx] });
            pos += headers[divider_idx].len - 1;
            divider += spacing[divider_idx] + 1;
            divider_idx += 1;
        } else {
            try stdout.print(" ", .{});
        }
    }

    divider_idx = 0;
    divider = 2 + spacing[divider_idx] + 1;
    divider_idx += 1;
    for (0..line_length + 1) |i| {
        if (i == 0) {
            try stdout.print("{s}", .{left_junction});
        } else if (i == line_length) {
            try stdout.print("{s}\n", .{right_junction});
        } else if (i == divider and divider_idx < spacing.len) {
            try stdout.print("{s}", .{intersection});
            divider += spacing[divider_idx] + 3;
            divider_idx += 1;
        } else {
            try stdout.print("{s}", .{horizontal});
        }
    }

    for (data.items, 1..) |item, idx| {
        divider_idx = 0;
        divider = 2 + spacing[divider_idx] + 1;
        divider_idx += 1;
        pos = 0;
        while (pos < line_length + 1) : (pos += 1) {
            if (pos == 0) {
                try stdout.print("{s}", .{vertical});
            } else if (pos == line_length) {
                try stdout.print("{s}\n", .{vertical});
            } else if (pos == 2) {
                try stdout.print("{s}", .{item.metadata.namespace});
                pos += item.metadata.namespace.len - 1;
            } else if (pos == divider) {
                if (divider_idx == 1) {
                    try stdout.print("{s} {s}", .{ vertical, item.metadata.name });
                    pos += item.metadata.name.len + 1;
                    divider += spacing[divider_idx] + 3;
                    divider_idx += 1;
                } else {
                    try stdout.print("{s} {s}", .{ vertical, item.metadata.creationTimestamp });
                    pos += item.metadata.creationTimestamp.len + 1;
                    divider += spacing[divider_idx];
                    divider_idx += 1;
                }
            } else {
                try stdout.print(" ", .{});
            }
        }

        divider_idx = 0;
        divider = 2 + spacing[divider_idx] + 1;
        divider_idx += 1;
        if (idx != data.items.len) {
            divider_idx = 0;
            divider = 2 + spacing[divider_idx] + 1;
            divider_idx += 1;
            for (0..line_length + 1) |i| {
                if (i == 0) {
                    try stdout.print("{s}", .{left_junction});
                } else if (i == line_length) {
                    try stdout.print("{s}\n", .{right_junction});
                } else if (i == divider and divider_idx < spacing.len) {
                    try stdout.print("{s}", .{intersection});
                    divider += spacing[divider_idx] + 3;
                    divider_idx += 1;
                } else {
                    try stdout.print("{s}", .{horizontal});
                }
            }
        } else {
            for (0..line_length + 1) |i| {
                if (i == 0) {
                    try stdout.print("{s}", .{bottom_left});
                } else if (i == line_length) {
                    try stdout.print("{s}\n\n", .{bottom_right});
                } else if (i == divider and divider_idx < spacing.len) {
                    try stdout.print("{s}", .{bottom_junction});
                    divider += spacing[divider_idx] + 3;
                    divider_idx += 1;
                } else {
                    try stdout.print("{s}", .{horizontal});
                }
            }
        }
    }
    try stdout.flush();
}
