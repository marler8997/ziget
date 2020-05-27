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
}

pub const SslConn = struct {
    ctx: *openssl.SSL_CTX,

    pub fn init(file: std.fs.File) !SslConn {
        // NOTE: zig unable to translate this function
        //pub const OpenSSL_add_all_algorithms = @compileError("unable to translate C expr: expected identifier");
        //openssl.OpenSSL_add_all_algorithms();

        // NOTE: zig unable to translate this function
        // pub const SSL_load_error_strings = @compileError("unable to translate C expr: expected identifier");
        //openssl.SSL_load_error_strings();

        const method = openssl.TLSv1_2_client_method();
        const ctx = openssl.SSL_CTX_new(method) orelse {
            openssl.ERR_print_errors_fp(stderr);
            return error.OpensslNewContextFailed;
        };
        errdefer openssl.SSL_CTX_free(ctx);
        const ssl = openssl.SSL_new(ctx);
        if (ssl == null) {
            openssl.ERR_print_errors_fp(stderr);
            return error.OpensslNewFailed;
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
