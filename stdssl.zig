const std = @import("std");

pub fn init() anyerror!void {
}

pub const SslConn = struct {
    pub const Pinned = struct { };

    stream: std.net.Stream,
    client: std.crypto.tls.Client,

    pub fn init(stream: std.net.Stream, serverName: []const u8, pinned: *Pinned) !SslConn {
        _ = pinned;

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        var ca_bundle = std.crypto.Certificate.Bundle{ };
        defer ca_bundle.deinit(arena.allocator());

        try ca_bundle.rescan(arena.allocator());
        return SslConn {
            .stream = stream,
            .client = try std.crypto.tls.Client.init(stream, ca_bundle, serverName),
        };
    }

    pub fn deinit(self: *SslConn) void {
        // TODO: do I need to close the stream?
        self.* = undefined;
    }

    pub fn read(self: *SslConn, data: []u8) !usize {
        return self.client.read(self.stream, data);
    }
    pub fn write(self: *SslConn, data: []const u8) !usize {
        return self.client.write(self.stream, data);
    }
};
