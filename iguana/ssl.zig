const std = @import("std");
const iguana = @import("iguana");

pub fn init() anyerror!void {
}

const Client = iguana.Client(
    std.net.Stream.Reader,
    std.net.Stream.Writer,
    iguana.ciphersuites.all,
    false, // TODO: should we provide the http/1.1 protocol?
);

pub const SslConn = struct {
    // state that an SslConn uses that is "pinned" to a fixed address
    // this has to be separate from SslConn until https://github.com/ziglang/zig/issues/7769 is implemented
    pub const Pinned = struct {
        rand: std.rand.DefaultCsprng,
        arena: std.heap.ArenaAllocator,
    };
    
    client: Client,

    pub fn init(file: std.net.Stream, serverName: []const u8, pinned: *Pinned) !SslConn {
        //var fbs = std.io.fixedBufferStream(@embedFile("../../iguanaTLS/test/DigiCertGlobalRootCA.crt.pem"));
        //var trusted_chain = try x509.TrustAnchorChain.from_pem(std.testing.allocator, fbs.reader());
        //defer trusted_chain.deinit();

        // @TODO Remove this once std.crypto.rand works in .evented mode
        pinned.rand = blk: {
            var seed: [std.rand.DefaultCsprng.secret_seed_length]u8 = undefined;
            try std.os.getrandom(&seed);
            break :blk std.rand.DefaultCsprng.init(seed);
        };
        pinned.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

        return SslConn {
            .client = try iguana.client_connect(.{
                .rand = pinned.rand.random(),
                .reader = file.reader(),
                .writer = file.writer(),
                .temp_allocator = pinned.arena.allocator(),
                .cert_verifier = .none,
                // TODO: do I need to add protocols here?  what does that do?
                //.protocols = &[_][]const u8{"http/1.1"},
                // TODO: I should support certificates
                //.cert_verifier = .default,
                //.trusted_certificates = trusted_chain.data.items,
            }, serverName),
        };
    }

    // TODO: This should be SslConn (not *SslConn)
    //       iquanaTLS will need to modify close_notify to take @This() instead of *@This()
    pub fn deinit(self: *SslConn) void {
        self.client.close_notify() catch {};
    }

    pub fn read(self: *SslConn, data: []u8) !usize {
        return self.client.reader().read(data);
    }
    pub fn write(self: *SslConn, data: []const u8) !usize {
        return self.client.writer().write(data);
    }
};
