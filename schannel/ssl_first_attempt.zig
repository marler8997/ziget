//
// This was my first attempt at implementing schannel.
// After starting this I found the "msspi" C library which implements a simple
// interface on top of schannel. I decided to switch to that for now.
// If/when that gets ported to Zig, this file can be used to know how to
// interact with the schannel API directly from Zig.
//
const std = @import("std");
const win32 = @import("win32");

usingnamespace win32.zig;
usingnamespace win32.api.system_services;
usingnamespace win32.api.com;
usingnamespace win32.api.security;


// Defining these consts because they are missing, see https://github.com/microsoft/win32metadata/issues/226
const RPC_C_AUTHN_LEVEL_PKT = 0x04;
const RPC_C_IMP_LEVEL_IMPERSONATE = 3;

// NOTE: these ones are flags to AcquireCredentialsHandle, file an issue for it?
const SECPKG_CRED_INBOUND = 1;
const SECPKG_CRED_OUTBOUND = 2;

// NOTE: these constants are missing
const ISC_REQ_CONFIDENTIALITY = 0x10;

// NOTE: these constants are missing
const SECURITY_NETWORK_DREP = 0;
const SECURITY_NATIVE_DREP = 16;

// NOTE: these constants are missing
const SECBUFFER_TOKEN = 2;

pub fn init() anyerror!void {
    //@panic("schannel init not implemented");

    // TODO: is this a one-time setup or per connection?
    //var auth_list : SOLE_AUTHENTICATION_LIST = undefined;

    // Initialize client security with no client certificate.
    //_ = CoInitializeSecurity( null, -1, null, null,
    //                    RPC_C_AUTHN_LEVEL_PKT,
    //                    RPC_C_IMP_LEVEL_IMPERSONATE, &auth_list,
    //                    @enumToInt(EOAC_NONE), null );
}

pub fn unexpectedSecurityError(err: i32) std.os.UnexpectedError {
    if (std.os.unexpected_error_tracing) {
        std.debug.print("Error: unexpected security error: 0x{x}\n", .{err});
        std.debug.dumpCurrentStackTrace(null);
        std.os.exit(1);
    }
    return error.Unexpected;
}

pub const SslConn = struct {
    // state that an SslConn uses that is "pinned" to a fixed address
    // this has to be separate from SslConn until https://github.com/ziglang/zig/issues/7769 is implemented
    pub const Pinned = struct {};

    stream: std.net.Stream,
    msg_reader: MsgReader(std.net.Stream.Reader),

    pub fn init(stream: std.net.Stream, server_name: []const u8, pinned: *Pinned) !SslConn {
        // TODO: initialize this properly
        var credential_handle : SecHandle = undefined;
        var lifetime: LARGE_INTEGER = undefined;

        // TODO: does this need to be mutable?
        //       the example uses a 1024 length buffer, not sure why
        //var package_name : [1024]TCHAR = undefined;
        //const negotiate = _T("Negotiate");
        //std.mem.copy(TCHAR, &package_name, negotiate);
        //package_name[negotiate.len] = 0;
        const negotiate : [:0]const u16 = L("Negotiate");

        switch (AcquireCredentialsHandle(
            null,
            //std.meta.assumeSentinel(&package_name, 0),
            // TODO: I think parameter is supposed to be const, but it isn't for some reason?
            removeConst(negotiate.ptr),
            SECPKG_CRED_OUTBOUND,
            null, null, null, null,
            &credential_handle,
            &lifetime,
        )) {
            SEC_E_OK => {},
            SEC_E_INSUFFICIENT_MEMORY => return error.OutOfMemory,
            SEC_E_INTERNAL_ERROR => return error.SspiInternalError,
            SEC_E_NO_CREDENTIALS => return error.SspiNoCredentials,
            SEC_E_NOT_OWNER => return error.SspiNotOwner,
            SEC_E_SECPKG_NOT_FOUND => return error.SspiUnknownSecurityPkg,
            SEC_E_UNKNOWN_CREDENTIALS => return error.SspiInvalidCredentials,
            else => |e| return unexpectedSecurityError(e),
        }
        //std.log.debug("[DEBUG] CredentialHandle {}:{}\n", .{credential_handle.dwLower, credential_handle.dwUpper});

        const target_name_wide = try std.unicode.utf8ToUtf16LeWithNull(std.heap.page_allocator, server_name);
        defer std.heap.page_allocator.free(target_name_wide);

        var security_context : SecHandle = undefined;

        const allocator = std.heap.page_allocator;
        var negotiate_buf = try allocator.allocFn(allocator, 4096, 1, 1, @returnAddress());
        defer {
            if (negotiate_buf.len > 0) {
                _ = allocator.resizeFn(allocator, negotiate_buf, 1, 0, 1, @returnAddress()) catch unreachable;
            }
        }
        std.log.debug("[SCHANNEL] negotiate buffer size is {}\n", .{negotiate_buf.len});

        var out_buf = SecBuffer {
            .cbBuffer = @intCast(u32, negotiate_buf.len),
            .BufferType = SECBUFFER_TOKEN,
            .pvBuffer = negotiate_buf.ptr,
        };
        var out_buf_desc = SecBufferDesc {
            .ulVersion = 0,
            .cBuffers = 1,
            .pBuffers = &out_buf,
        };
        var context_attrs : u32 = undefined;
        var expiry : LARGE_INTEGER = undefined;

        var need_complete_auth_token = false;
        var need_continue = false;
        switch(InitializeSecurityContext(
            &credential_handle,
            null, //&security_context,
            // TODO: this type is wrong, should be a "Many" pointer, not a "One" pointer
            @ptrCast(*u16, target_name_wide.ptr),
            ISC_REQ_CONFIDENTIALITY,
            0,
            SECURITY_NATIVE_DREP,
            null, //&in_buf_desc,
            0,
            &security_context,
            &out_buf_desc,
            &context_attrs,
            &expiry
        )) {
            // Success Codes
            SEC_E_OK => {}, // The security context was successfully initialized. There is no need for another InitializeSecurityContext (Schannel) call. If the function returns an output token, that is, if the SECBUFFER_TOKEN in pOutput is of nonzero length, that token must be sent to the server.
            SEC_I_COMPLETE_AND_CONTINUE => {
                //The client must call CompleteAuthToken and then pass the output to the server. The client then waits for a returned token and passes it, in another call, to InitializeSecurityContext (Schannel).
                need_complete_auth_token = true;
                need_continue = true;
            },
            SEC_I_COMPLETE_NEEDED => {
                //The client must finish building the message and then call the CompleteAuthToken function.
                need_complete_auth_token = true;
            },
            SEC_I_CONTINUE_NEEDED => {
                //The client must send the output token to the server and wait for a return token. The returned token is then passed in another call to InitializeSecurityContext (Schannel). The output token can be empty.
                need_continue = true;
            },
            SEC_I_INCOMPLETE_CREDENTIALS => @panic("not impl"), //The server has requested client authentication, and the supplied credentials either do not include a certificate or the certificate was not issued by a certification authority (CA) that is trusted by the server. For more information, see Remarks.
            SEC_E_INCOMPLETE_MESSAGE => @panic("not impl"),//Data for the whole message was not read from the wire.
                                           // When this value is returned, the pInput buffer contains a SecBuffer structure with a BufferType member of SECBUFFER_MISSING. The cbBuffer member of SecBuffer contains a value that indicates the number of additional bytes that the function must read from the client before this function succeeds. While this number is not always accurate, using it can help improve performance by avoiding multiple calls to this function.

            // Fail Codes
            SEC_E_INSUFFICIENT_MEMORY => return error.OutOfMemory,
            SEC_E_INTERNAL_ERROR => return error.SspiInternalError,
            SEC_E_INVALID_HANDLE => unreachable,
            SEC_E_INVALID_TOKEN => return error.SspiInvalidToken,
            SEC_E_LOGON_DENIED => return error.SspiLoginDenied,
            SEC_E_NO_AUTHENTICATING_AUTHORITY => return error.SspiNoAuth,
            SEC_E_NO_CREDENTIALS => return error.SspiNoCredentials,
            SEC_E_TARGET_UNKNOWN => return error.SspiTargetUnknown,
            SEC_E_UNSUPPORTED_FUNCTION => unreachable,
            SEC_E_WRONG_PRINCIPAL => return error.SspiWrongPrincipal,
            SEC_E_APPLICATION_PROTOCOL_MISMATCH => return error.SspiApplicationProtocolMismatch,
            else => |e| return unexpectedSecurityError(e),
        }

        if (need_complete_auth_token)
        {
            @panic("CompleteAuthToken is not implemented");
        }

        var conn = SslConn {
            .stream = stream,
            // TODO: what allocator to use here?
            .msg_reader = MsgReader(std.net.Stream.Reader).init(stream.reader()),
        };

        {
            const token = negotiate_buf[0 .. out_buf.cbBuffer];
            std.log.debug("[SCHANNEL] token buffer {} bytes: 0x{x}", .{token.len, token});
            const written = try conn.write(token);
            std.debug.assert(written == token.len);
        }

        if (need_continue) {
            while (need_continue) {
                try conn.msg_reader.readLen();
                const msg_len = conn.msg_reader.msg_left;
                if (negotiate_buf.len < msg_len) {
                    std.log.debug("[SCHANNEL] expanding buffer from {} to {}", .{negotiate_buf.len, msg_len});
                    std.log.debug("0x{x}", .{msg_len});
                    try reallocNoPreserve(allocator, &negotiate_buf, 1, msg_len, 1, @returnAddress());
                }
                const msg = negotiate_buf[0..msg_len];
                try conn.msg_reader.readCurrentMsgFull(msg);

                std.log.err("need_continue not implemented", .{});
                std.os.exit(1);
            }
        }
        return conn;
    }
    pub fn deinit(self: SslConn) void {
        @panic("TODO: implement deinit");
    }

    pub fn read(self: *SslConn, data: []u8) !usize {
        return self.msg_reader.read(data);
    }
    pub fn write(self: SslConn, data: []const u8) !usize {
        {
            const len = @intCast(u32, data.len);
            const len_bytes = @ptrCast([*]const u8, &len)[0..4];
            try self.stream.writer().writeAll(len_bytes);
        }
        try self.stream.writer().writeAll(data);
        return data.len;
    }
};

// TODO: move to std/mem/Allocator.zig
fn reallocNoPreserve(allocator: *std.mem.Allocator, buf: *[]u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) std.mem.Allocator.Error!void {
    std.debug.assert(new_len > buf.*.len);
    buf.*.len = allocator.resizeFn(allocator, buf.*, buf_align, new_len, len_align, ret_addr) catch {
        std.debug.assert(0 == allocator.resizeFn(allocator, buf.*, buf_align, 0, len_align, ret_addr) catch unreachable);
        buf.* = &[0]u8 {};
        buf.* = try allocator.allocFn(allocator, new_len, buf_align, len_align, ret_addr);
        std.debug.assert(buf.*.len >= new_len);
        return;
    };
}

fn MsgReader(comptime Reader: type) type { return struct {
    reader: Reader,
    msg_left: u32,

    pub fn init(reader: Reader) @This() {
        return .{
            .reader = reader,
            .msg_left = 0,
        };
    }

    pub fn readLen(self: *@This()) !void {
        std.debug.assert(self.msg_left == 0);
        var len : u32 = undefined;
        var len_bytes = @ptrCast([*]u8, &len)[0..4];
        try self.reader.readNoEof(len_bytes);
        // IS THIS POSSIBLE?
        std.debug.assert(len != 0);
        self.msg_left = len;
    }

    pub fn readCurrentMsgFull(self: *@This(), data: []u8) !void {
        std.debug.assert(self.msg_left == data.len);
        try self.reader.readNoEof(data);
        self.msg_left = 0;
    }

    pub fn read(self: *@This(), data: []u8) !usize {
        if (self.msg_left == 0) {
            try self.readLen();
        }

        const len = @intCast(u32, try self.reader.read(data[0 .. std.math.min(self.msg_left, data.len)]));
        self.msg_left -= len;
        return len;
    }
};}


// TODO: move this somewhere
pub fn RemoveConst(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Pointer => |info| return @Type(std.builtin.TypeInfo { .Pointer = .{
            .is_const     = false,
            .size         = info.size,
            .is_volatile  = info.is_volatile,
            .alignment    = info.alignment,
            .child        = info.child,
            .is_allowzero = info.is_allowzero,
            .sentinel     = info.sentinel,
        }}),
        else => {},
    }
    @compileError("removeConst does not support: " ++ @typeName(T));
}
fn removeConst(a: anytype) RemoveConst(@TypeOf(a)) {
    return @intToPtr(RemoveConst(@TypeOf(a)), @ptrToInt(a));
}
