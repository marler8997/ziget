const std = @import("std");

const openssl = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
});

extern "c" var stderr: [*c]openssl.FILE;

pub fn init() anyerror!void {
    std.debug.warn("[DEBUG] openssl init\n", .{});

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
    ctx: *openssl.SSL_CTX,

    pub fn init(file: std.fs.File, serverName: []const u8) !SslConn {
        //const method = openssl.TLSv1_2_client_method();
        //const method = openssl.SSLv3_method();
        //const method = openssl.TLS_method();
        const method = openssl.SSLv23_method();
        const ctx = openssl.SSL_CTX_new(method) orelse {
            openssl.ERR_print_errors_fp(stderr);
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
        const ssl = openssl.SSL_new(ctx);
        if (ssl == null) {
            openssl.ERR_print_errors_fp(stderr);
            return error.OpensslNewFailed;
        }

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
            openssl.ERR_print_errors_fp(stderr);
            return error.OpensslSetHostNameFailed;
        }

        if (1 != openssl.SSL_set_fd(ssl, file.handle)) {
            openssl.ERR_print_errors_fp(stderr);
            return error.OpensslSetFdFailed;
        }
        {
            const result = openssl.SSL_connect(ssl);
            if (result != 1) {
                std.debug.warn("SSL_connect failed with {}\n", .{result});
                openssl.ERR_print_errors_fp(stderr);
                return error.OpensslConnectFailed;
            }
        }

        return SslConn { .ctx = ctx };
    }
    pub fn deinit(self: SslConn) void {
        openssl.SSL_CTX_free(self.ctx);
    }
};
