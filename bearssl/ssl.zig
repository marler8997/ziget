const std = @import("std");
const bearssl = @import("bearssl");

const bearssl_log = std.log.scoped(.bearssl);

pub fn init() anyerror!void {
    // TODO: insert any one-time bearssl initialization code here, if any
}

pub const SslConn = struct {
    // state that an SslConn uses that is "pinned" to a fixed address
    // this has to be separate from SslConn until https://github.com/ziglang/zig/issues/7769 is implemented
    pub const Pinned = struct {
        engine: bearssl.x509.Minimal,
        client: bearssl.Client,
        stream: std.net.Stream,
    };

    stream: bearssl.Stream(*std.net.Stream, *std.net.Stream),

    pub fn init(stream: std.net.Stream, serverName: []const u8, pinned: *Pinned) !SslConn {
        // TODO: what can I do about this allocator?
        const trust_anchor = bearssl.TrustAnchorCollection.init(std.heap.c_allocator);
        pinned.* = .{
            .engine = bearssl.x509.Minimal.init(trust_anchor),
            .client = bearssl.Client.init(pinned.engine.getEngine()),
            .stream = stream,
        };
        return SslConn {
            .stream = bearssl.initStream(pinned.client.getEngine(), &pinned.stream, &pinned.stream),
        };
    }
    // TODO: should take SslConn rather than *SslConn
    //       will need to modify zig-bearssl to do this
    pub fn deinit(self: *SslConn) void {
        self.stream.close() catch @panic("bearssl stream close failed");
    }

    pub fn read(self: *SslConn, data: []u8) !usize {
        bearssl_log.debug("read {} bytes", .{data.len});
        return self.stream.read(data);
    }
    pub fn write(self: *SslConn, data: []const u8) !usize {
        bearssl_log.debug("write {} bytes", .{data.len});
        const result = try self.stream.write(data);
        if (result == 0) {
            return error.WriteReturned0;
        }
        // TODO: I think we're supposed to flush here but not 100% sure
        try self.stream.flush();
        return result;
    }
};
