const std = @import("std");

const win = std.os.windows;
const GetLastError = win.kernel32.GetLastError;

const schannel_log = std.log.scoped(.schannel);

const c = @cImport({
    @cDefine("_WIN32", {});
    @cDefine("WIN32", {});
    // there seems to be a bug in msspi.h where they are typedef'ing WCHAR with wchar_t
    // however they don't seem to be including the header file for wchar_t
    @cInclude("stdint.h");
    @cDefine("wchar_t", "uint16_t");
    @cInclude("msspi.h");
});

pub fn init() anyerror!void {
}

pub const SslConn = struct {
    // state that an SslConn uses that is "pinned" to a fixed address
    // this has to be separate from SslConn until https://github.com/ziglang/zig/issues/7769 is implemented
    pub const Pinned = struct {
        stream: std.net.Stream,
        last_read_error: ?anyerror,
        last_write_error: ?anyerror,
    };

    msspi_handle: c.MSSPI_HANDLE,
    pinned: *Pinned,
    host_name: [:0]u8,

    pub fn init(stream: std.net.Stream, server_name: []const u8, pinned: *Pinned) !SslConn {
        const local_server_name = try std.heap.page_allocator.dupeZ(u8, server_name);
        errdefer std.heap.page_allocator.free(local_server_name);

        pinned.* = .{
            .stream = stream,
            .last_read_error = undefined,
            .last_write_error = undefined,
        };
        var conn = SslConn {
            .msspi_handle = c.msspi_open(pinned, msspi_read_cb, msspi_write_cb),
            .pinned = pinned,
            .host_name = local_server_name,
        };
        if (conn.msspi_handle == null) {
            // TODO: use GetLastError to return a specific error?  Also set it to 0 beforehand if I do this.
            schannel_log.err("msspi_open failed, GetLastError()={}", .{GetLastError()});
            return error.MsspiOpenFailed;
        }

        if (1 != c.msspi_set_hostname(conn.msspi_handle, conn.host_name.ptr)) {
            // TODO: use GetLastError to return a specific error?  Also set it to 0 beforehand if I do this.
            schannel_log.err("msspi_set_hostname failed, GetLastError()={}", .{GetLastError()});
            return error.MsspiSetHostname;
        }

        const connect_result = c.msspi_connect(conn.msspi_handle);
        if (connect_result <= 0)
        {
            // TODO: use GetLastError to return a specific error?  Also set it to 0 beforehand if I do this.
            schannel_log.err("msspi_connect failed, returned {}, GetLastError()={}", .{connect_result, GetLastError()});
            return error.MsspiConnectFailed;
        }

        return conn;
    }
    pub fn deinit(self: SslConn) void {
        std.heap.page_allocator.free(self.host_name);
    }

    fn msspi_read_cb(cb_arg: ?*c_void, buf: ?*c_void, len: c_int) callconv(.C) c_int {
        const pinned = @ptrCast(*Pinned, @alignCast(@alignOf(Pinned), cb_arg));
        schannel_log.debug("read_cb: reading {}...", .{@intCast(usize, len)});
        const result = pinned.stream.read(@ptrCast([*]u8, buf)[0..@intCast(usize, len)]) catch |err| {
            pinned.last_read_error = err;
            return -1;
        };
        schannel_log.debug("read_cb: received {} bytes", .{result});
        return @intCast(c_int, result);
    }
    fn msspi_write_cb(cb_arg: ?*c_void, buf: ?*const c_void, len: c_int) callconv(.C) c_int {
        const pinned = @ptrCast(*Pinned, @alignCast(@alignOf(Pinned), cb_arg));
        const result = pinned.stream.write(@ptrCast([*]const u8, buf)[0..@intCast(usize, len)]) catch |err| {
            pinned.last_write_error = err;
            return -1;
        };
        schannel_log.debug("write_cb: sent {} (out of {}) bytes", .{result, len});
        return @intCast(c_int, result);
    }

    pub fn read(self: SslConn, data: []u8) !usize {
        self.pinned.last_read_error = null;
        schannel_log.debug("read {} bytes", .{@intCast(c_int, data.len)});
        const result = c.msspi_read(self.msspi_handle, data.ptr, @intCast(c_int, data.len));
        schannel_log.debug("read returned {}", .{result});
        if (result < 0) {
            if (self.pinned.last_read_error) |err| {
                return err;
            }
            return error.ReadReturnedNegative;
        }
        return @intCast(usize, result);
    }
    pub fn write(self: SslConn, data: []const u8) !usize {
        var total_written : usize = 0;
        while (total_written < data.len) {
            var remaining = data[total_written..];
            const next_len = if (remaining.len > std.math.maxInt(c_int)) std.math.maxInt(c_int)
                else  @intCast(c_int, remaining.len);
            self.pinned.last_write_error = null;
            schannel_log.debug("write {} bytes", .{next_len});
            const written = c.msspi_write(self.msspi_handle, remaining.ptr, next_len);
            schannel_log.debug("write returned {}", .{written});
            if (written <= 0) {
                if (self.pinned.last_write_error) |err| {
                    return err;
                }
                break;
            }
            total_written += @intCast(usize, written);
        }
        return total_written;
    }
};
