const std = @import("std");
const builtin = @import("builtin");

const openssl = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
});

const c = if (builtin.os.tag == .windows) struct { } else struct {
    pub extern "c" var stderr: *openssl.FILE;
};

fn ERR_print_errors_fp() void {
    // windows doesn't have `stderr`, so not sure what to do here yet
    if (builtin.os.tag == .windows) {
        std.debug.print("windows openssl error, unable to print it yet\n", .{});
        return;
    }
    openssl.ERR_print_errors_fp(c.stderr);
}

pub fn init() anyerror!void {
    std.debug.print("[DEBUG] openssl init\n", .{});

    // NOTE: zig unable to translate this function
    // pub const SSL_library_init = @compileError("unable to translate C expr: expected identifier");
    //openssl.SSL_library_init();
    if (1 != openssl.OPENSSL_init_ssl(0, null))
        return error.OpensslInitSslFailed;

    // NOTE: zig unable to translate this function
    //pub const OpenSSL_add_all_algorithms = @compileError("unable to translate C expr: expected identifier");
    //openssl.OpenSSL_add_all_algorithms();
    // NOTE: this should be roughly the same thing
    if (1 != openssl.OPENSSL_init_crypto(
                      openssl.OPENSSL_INIT_ADD_ALL_CIPHERS
                    | openssl.OPENSSL_INIT_ADD_ALL_DIGESTS
                    //| openssl.OPENSSL_INIT_LOAD_CONFIG
                    , null)) {
        return error.OpensslInitCryptoFailed;
    }

    // NOTE: zig unable to translate this function
    // pub const SSL_load_error_strings = @compileError("unable to translate C expr: expected identifier");
    //openssl.SSL_load_error_strings();

    //openssl.OPENSSL_config(null);

}

pub const SslConn = struct {
    // state that an SslConn uses that is "pinned" to a fixed address
    // this has to be separate from SslConn until https://github.com/ziglang/zig/issues/7769 is implemented
    pub const Pinned = struct {};

    ctx: *openssl.SSL_CTX,
    ssl: *openssl.SSL,

    pub fn init(file: std.net.Stream, serverName: []const u8, pinned: *Pinned) !SslConn {
        _ = pinned;

        //const method = openssl.TLSv1_2_client_method();
        //const method = openssl.SSLv3_method();
        //const method = openssl.TLS_method();
        const method = openssl.SSLv23_method();
        const ctx = openssl.SSL_CTX_new(method) orelse {
            ERR_print_errors_fp();
            return error.OpensslNewContextFailed;
        };
        errdefer openssl.SSL_CTX_free(ctx);

        // TODO: set server name?
        //openssl.SSL_CTX_set_tlsext_servername_callback();
        //openssl.SSL_CTX_set_tlsext_servername_arg(ctx, @as(usize, 0));

        _ = openssl.SSL_CTX_set_options(ctx, openssl.SSL_OP_NO_SSLv2);
        _ = openssl.SSL_CTX_set_options(ctx, openssl.SSL_OP_NO_SSLv3);
        //_ = openssl.SSL_CTX_set_options(ctx, openssl.SSL_OP_NO_TLSv1);
        //_ = openssl.SSL_CTX_set_options(ctx, openssl.SSL_OP_NO_TLSv1_1);
        const ssl = openssl.SSL_new(ctx) orelse {
            ERR_print_errors_fp();
            return error.OpensslNewFailed;
        };
        // TODO: does ssl need to be freed??? SSL_free?

        // TEMPORARY HACK to get around the non-const
        // https://ziglang.org doesn't work without the servername being set
        // it sends back and alert with handshake_failure
        var buf : [100]u8 = undefined;
        std.mem.copy(u8, &buf, serverName);
        buf[serverName.len] = 0;
        const hostnameSlice : []u8 = &buf;
        //if (1 != openssl.SSL_set_tlsext_host_name(ssl, hostnameSlice.ptr)) {
        if (1 != openssl.SSL_ctrl(ssl, openssl.SSL_CTRL_SET_TLSEXT_HOSTNAME,
            openssl.TLSEXT_NAMETYPE_host_name, hostnameSlice.ptr)) {
            ERR_print_errors_fp();
            return error.OpensslSetHostNameFailed;
        }

        if (1 != openssl.SSL_set_fd(ssl, streamToCHandle(file))) {
            ERR_print_errors_fp();
            return error.OpensslSetFdFailed;
        }
        {
            const result = openssl.SSL_connect(ssl);
            if (result != 1) {
                std.debug.print("SSL_connect failed with {d}\n", .{result});
                ERR_print_errors_fp();
                return error.OpensslConnectFailed;
            }
        }

        return SslConn {
            .ctx = ctx,
            .ssl = ssl,
        };
    }
    pub fn deinit(self: SslConn) void {
        openssl.SSL_CTX_free(self.ctx);
    }

    //pub const ReadError = FnError(@TypeOf(readBoth));
    //pub const WriteError = FnError(@TypeOf(writeBoth));
    pub const ReadError = error { };
    pub const WriteError = error { };
    pub const Reader = std.io.Reader(*SslConn, ReadError, read);
    pub const Writer = std.io.Writer(*SslConn, WriteError, write);

    pub fn reader(self: *@This()) Reader {
        return .{ .context = self };
    }

    pub fn writer(self: *@This()) Writer {
        return .{ .context = self };
    }

    pub fn read(self: *SslConn, data: []u8) !usize {
        var readSize : usize = undefined;
        const result = openssl.SSL_read_ex(self.ssl, data.ptr, data.len, &readSize);
        if (1 == result)
            return readSize;

        const err = openssl.SSL_get_error(self.ssl, result);
        switch (err) {
            openssl.SSL_ERROR_ZERO_RETURN => return 0,
            else => std.debug.panic("SSL_read failed with {d}\n", .{err}),
        }
    }
    pub fn write(self: *SslConn, data: []const u8) !usize {
        // TODO: and writeSize with c_int mask, it's ok if we don't write all the data
        const result = openssl.SSL_write(self.ssl, data.ptr, @intCast(c_int, data.len));
        if (result <= 0) {
            const err = openssl.SSL_get_error(self.ssl, result);
            switch (err) {
                openssl.SSL_ERROR_NONE => unreachable,
                openssl.SSL_ERROR_ZERO_RETURN => unreachable,
                openssl.SSL_ERROR_WANT_READ
                ,openssl.SSL_ERROR_WANT_WRITE
                ,openssl.SSL_ERROR_WANT_CONNECT
                ,openssl.SSL_ERROR_WANT_ACCEPT
                ,openssl.SSL_ERROR_WANT_X509_LOOKUP
                ,openssl.SSL_ERROR_WANT_ASYNC
                ,openssl.SSL_ERROR_WANT_ASYNC_JOB
                ,openssl.SSL_ERROR_WANT_CLIENT_HELLO_CB
                ,openssl.SSL_ERROR_SYSCALL
                ,openssl.SSL_ERROR_SSL
                    => std.debug.panic("SSL_write failed with {d}\n", .{err}),
                else
                    => std.debug.panic("SSL_write failed with {d}\n", .{err}),
            }
        }
        return @intCast(usize, result);
    }
};

fn streamToCHandle(file: std.net.Stream)
    if (builtin.os.tag == .windows) c_int else std.os.socket_t {

    if (builtin.os.tag == .windows)
        return @intCast(c_int, @ptrToInt(file.handle));
    return file.handle;
}
