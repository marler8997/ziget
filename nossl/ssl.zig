const std = @import("std");

pub fn init() anyerror!void {
    std.debug.print("[DEBUG] nossl init\n", .{});
}

pub const SslConn = struct {
    // state that an SslConn uses that is "pinned" to a fixed address
    // this has to be separate from SslConn until https://github.com/ziglang/zig/issues/7769 is implemented
    pub const Pinned = struct {};

    pub fn init(file: std.net.Stream, serverName: []const u8, pinned: *Pinned) !SslConn {
        _ = file;
        _ = serverName;
        _ = pinned;
        return error.NoSslConfigured;
    }
    pub fn deinit(self: SslConn) void {
        _ = self;
    }
    pub fn read(self: SslConn, data: []u8) !usize {
        _ = self;
        _ = data;
        @panic("nossl has been configured");
    }
    pub fn write(self: SslConn, data: []const u8) !usize {
        _ = self;
        _ = data;
        @panic("nossl has been configured");
    }
};
