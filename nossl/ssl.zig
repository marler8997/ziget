const std = @import("std");

pub fn init() anyerror!void {
    std.debug.warn("[DEBUG] nossl init\n", .{});
}