const std = @import("std");

pub fn init() anyerror!void {
    std.debug.warn("[DEBUG] nossl init\n", .{});
}

pub const SslConn = struct {
    pub fn init(file: std.fs.File, serverName: []const u8) !SslConn {
        return error.NoSslConfigured;
    }
    pub fn deinit(self: SslConn) void { }
};
