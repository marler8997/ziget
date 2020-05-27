const std = @import("std");

// TODO: why isn't this working?
//const stdext = @import("stdext");
const stdext= @import("../src-stdext/stdext.zig");
const readwrite = stdext.readwrite;
const ReaderWriter = readwrite.ReaderWriter;

pub fn init() anyerror!void {
    std.debug.warn("[DEBUG] nossl init\n", .{});
}

pub const SslConn = struct {
    rw: ReaderWriter,
    pub fn init(file: std.fs.File, serverName: []const u8) !SslConn {
        return error.NoSslConfigured;
    }
    pub fn deinit(self: SslConn) void { }
};
