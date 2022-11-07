const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const net = std.net;
const testing = std.testing;

const Allocator = mem.Allocator;

const net_stream = @import("./net_stream.zig");
const NetStream = net_stream.NetStream;

const urlmod = @import("./url.zig");
const Url = urlmod.Url;

const ziget = @import("../ziget.zig");
const http = ziget.http;

const ssl = @import("ssl");

const DownloadResult = union(enum) {
    Success: void,
    Redirect: []u8,
};

/// Options for a download
pub const DownloadOptions = struct {
    //pub const Flag = struct {
        //pub const bufferIsMaxHttpRequest  : u8 = 0x01;
        //pub const bufferIsMaxHttpResponse : u8 = 0x02;
    //};
    flags: u8,
    allocator: Allocator,
    maxRedirects: u32,
    forwardBufferSize: u32,
    maxHttpResponseHeaders: u32,
    onHttpRequest: switch (builtin.zig_backend) {
        .stage1 => fn(request: []const u8) void,
        else => *const fn(request: []const u8) void,
    },
    onHttpResponse: switch (builtin.zig_backend) {
        .stage1 => fn(response: []const u8) void,
        else => *const fn(response: []const u8) void,
    },
};
/// State that can change during a download
pub const DownloadState = struct {
    // TODO: use bufferState to manage the shared buffer in DownloadOptions
    const BufferState = enum {
        available,
    };
    bufferState: BufferState,
    redirects: u32,
    pub fn init() DownloadState {
        return .{
            .bufferState = .available,
            .redirects = 0,
        };
    }
};

fn optionalFree(allocator: Allocator, comptime T: type, optionalBuf: ?[]T) void {
    if (optionalBuf) |buf| {
        allocator.free(buf);
    }
}

// have to use anyerror for now because download and downloadHttp recursively call each other
pub fn download(url: Url, writer: anytype, options: DownloadOptions, state: *DownloadState) !void {
    var urlStringToFree: ?[]u8 = null;
    defer optionalFree(options.allocator, u8, urlStringToFree);

    var nextUrl = url;

    while (true) {
        const result = switch (nextUrl) {
            .None => @panic("no scheme not implemented"),
            .Unknown => return error.UnknownUrlScheme,
            .Http => |httpUrl| try downloadHttpOrRedirect(httpUrl, writer, options),
        };
        switch (result) {
            .Success => return,
            .Redirect => |redirectUrlString| {
                optionalFree(options.allocator, u8, urlStringToFree);
                urlStringToFree = redirectUrlString;

                state.redirects += 1;
                if (state.redirects > options.maxRedirects)
                    return error.MaxRedirects;
                nextUrl = try ziget.url.parseUrl(redirectUrlString);
            },
        }
    }
}

// TODO: should I provide this function?
//pub fn downloadHttp(options: *DownloadOptions, httpUrl: Url.Http) !void {
//    switch (try downloadHttpOrRedirect(options, httpUrl)) {
//        .Success => return,
//        .Redirect => |redirectUrl| {
//            options.redirects += 1;
//            if (options.redirect > options.maxRedirects)
//                return error.MaxRedirects;
//            return download(options, redirectUrl);
//        },
//    }
//}

pub fn httpAlloc(allocator: Allocator, method: []const u8, resource: []const u8, host: []const u8,headers: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator,
           "{s} {s} HTTP/1.1\r\n"
        ++ "Host: {s}\r\n"
        ++ "{s}"
        ++ "\r\n", .{
        method, resource, host, headers});
}

//pub fn sendHttpGet(allocator: Allocator, writer: anytype, httpUrl: Url.Http, keepAlive: bool) !void {
//    const request = try httpAlloc(allocator, "GET", httpUrl.str,
//        httpUrl.getHostPortString(),
//        if (keepAlive) "Connection: keep-alive\r\n" else "Connection: close\r\n"
//    );
//    defer allocator.free(request);
//
//    std.debug.print("--------------------------------------------------------------------------------\n", .{});
//    std.debug.print("Sending HTTP Request...\n", .{});
//    std.debug.print("--------------------------------------------------------------------------------\n", .{});
//    std.debug.print("{s}", .{request});
//    try writer.writeAll(request);
//}

const HttpResponse = struct {
    buffer: []u8,
    httpLimit: usize,
    dataLimit: usize,
    pub fn getHttpSlice(self: HttpResponse) []u8 {
        return self.buffer[0..self.httpLimit];
    }
    pub fn hasData(self: HttpResponse) bool {
        return self.dataLimit > self.httpLimit;
    }
    pub fn getDataSlice(self: HttpResponse) []u8 {
        return self.buffer[self.httpLimit..self.dataLimit];
    }
};
pub fn readHttpResponse(allocator: Allocator, reader: anytype, initialBufferLen: usize, maxBufferLen: usize) !HttpResponse {
    var buffer = try allocator.alloc(u8, initialBufferLen);
    errdefer allocator.free(buffer);

    var totalRead : usize = 0;
    while (true) {
        if (totalRead >= buffer.len) {
            if (buffer.len >= maxBufferLen)
                return error.HttpResponseTooBig;
            // TODO: is this right with the errdefer free?
            buffer = try allocator.realloc(buffer, std.math.min(maxBufferLen, 2 * buffer.len));
        }
        var len = try reader.read(buffer[totalRead..]);
        if (len == 0) return error.HttpResponseIncomplete;
        var headersLimit = totalRead;
        totalRead = totalRead + len;
        if (headersLimit <= 3)
            headersLimit += 3;
        while (headersLimit < totalRead) {
            headersLimit += 1;
            if (ziget.mem.cmp(u8, buffer[headersLimit - 4..].ptr, "\r\n\r\n", 4))
                return HttpResponse { .buffer = buffer, .httpLimit = headersLimit, .dataLimit = totalRead };
        }
    }
}

// TODO: call sendFile on linux so we don't have to read the data into memory
pub fn forward(buffer: []u8, reader: anytype, writer: anytype) !void {
    while (true) {
        var len = try reader.read(buffer);
        if (len == 0) break;
        try writer.writeAll(buffer[0..len]);
    }
}

pub fn downloadHttpOrRedirect(httpUrl: Url.Http, writer: anytype, options: DownloadOptions) !DownloadResult {
    const file = try net.tcpConnectToHost(options.allocator, httpUrl.getHostString(), httpUrl.getPortOrDefault());
    defer {
        // TODO: file.shutdown()???
        file.close();
    }
    var stream = NetStream.initStream(&file);

    var sslConnPinned : ssl.SslConn.Pinned = undefined;
    var sslConn : ssl.SslConn = undefined;
    if (httpUrl.secure) {
        sslConn = try ssl.SslConn.init(file, httpUrl.getHostString(), &sslConnPinned);
        stream = NetStream.initSsl(&sslConn);
    }
    defer { if (httpUrl.secure) sslConn.deinit(); }

    {
        const request = try httpAlloc(options.allocator, "GET", httpUrl.str,
            httpUrl.getHostPortString(),
            "Connection: close\r\n",
        );
        defer options.allocator.free(request);
        options.onHttpRequest(request);
        try stream.writer().writeAll(request);
    }

    {
        const response = try readHttpResponse(options.allocator, stream.reader(),
            std.math.min(4096, options.maxHttpResponseHeaders), options.maxHttpResponseHeaders);
        defer options.allocator.free(response.buffer);
        const httpResponse = response.getHttpSlice();
        options.onHttpResponse(httpResponse);
        {
            const status = try http.parse.parseHttpStatusLine(httpResponse);
            if (status.code != 200) {
                const headers = httpResponse[status.len..];
                if (status.code == 301) {
                    // TODO: create copy of location url
                    const location = (try http.parse.parseHeaderValue(headers, "Location")) orelse
                        return error.HttpRedirectNoLocation;
                    const locationCopy = try options.allocator.dupe(u8, location);
                    return DownloadResult { .Redirect = locationCopy };
                }
                std.debug.print("Non 200 status code: {d} {s}\n", .{status.code, status.getMsg(httpResponse)});
                return error.HttpNon200StatusCode;
            }
        }

        if (response.hasData()) {
            try writer.writeAll(response.getDataSlice());
        }
    }
    var buffer = try options.allocator.alloc(u8, options.forwardBufferSize);
    defer options.allocator.free(buffer);
    try forward(buffer, stream.reader(), writer);
    return DownloadResult.Success;
}
