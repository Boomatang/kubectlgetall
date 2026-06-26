const std = @import("std");

pub const Level = enum { info, debug, @"error", warn };

pub var log_level: std.log.Level = .info;

pub fn setLogLevel(level: Level) void {
    log_level = switch (level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .@"error" => .err,
    };
}

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = comptime blk: {
        if (scope == .default)
            break :blk "[" ++ level.asText() ++ "] ";
        break :blk "[" ++ level.asText() ++ "][" ++ @tagName(scope) ++ "] ";
    };

    if (@intFromEnum(level) <= @intFromEnum(log_level)) {
        std.debug.print(prefix ++ format ++ "\n", args);
    }
}
