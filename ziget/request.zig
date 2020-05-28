const std = @import("std");
const mem = std.mem;
const net = std.net;
const testing = std.testing;

const Allocator = mem.Allocator;

const stdext = @import("stdext");
const readwrite = stdext.readwrite;
const Reader = readwrite.Reader;
const Writer = readwrite.Writer;
const FileReaderWriter = readwrite.FileReaderWriter;

const urlmod = @import("./url.zig");
const Url = urlmod.Url;

const ziget = @import("../ziget.zig");
const http = ziget.http;

const ssl = @import("ssl");

const DownloadResult = union(enum) {
    Success: void,
    Redirect: Url,
};

pub const DownloadOptions = struct {
    pub const Flag = struct {
        pub const bufferIsMaxHttpRequest  : u8 = 0x01;
        pub const bufferIsMaxHttpResponse : u8 = 0x02;
    };
    flags: u8,
    allocator: *Allocator,
    maxRedirects: u32,
    buffer: []u8,
    redirects: u32,
};

// have to use anyerror for now because download and downloadHttp recursively call each other
pub fn download(options: *DownloadOptions, url: Url, writer: *Writer) !void {
    var nextUrl = url;
    while (true) {
        const result = switch (nextUrl) {
            .None => @panic("no scheme not implemented"),
            .Unknown => return error.UnknownUrlScheme,
            .Http => |httpUrl| try downloadHttpOrRedirect(options, httpUrl, writer),
        };
        switch (result) {
            .Success => return,
            .Redirect => |redirectUrl| {
                options.redirects += 1;
                if (options.redirects > options.maxRedirects)
                    return error.MaxRedirects;
                nextUrl = redirectUrl;
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

pub fn httpAlloc(allocator: *Allocator, method: []const u8, resource: []const u8, host: []const u8,headers: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator,
           "{} {} HTTP/1.1\r\n"
        ++ "Host: {}\r\n"
        ++ "{}"
        ++ "\r\n", .{
        method, resource, host, headers});
}

pub fn sendHttpGet(allocator: *Allocator, writer: *Writer, httpUrl: Url.Http, keepAlive: bool) !void {
    const request = try httpAlloc(allocator, "GET", httpUrl.str,
        httpUrl.getHostPortString(),
        if (keepAlive) "Connection: keep-alive\r\n" else "Connection: close\r\n"
    );
    defer allocator.free(request);
    std.debug.warn("--------------------------------------------------------------------------------\n", .{});
    std.debug.warn("Sending HTTP Request...\n", .{});
    std.debug.warn("--------------------------------------------------------------------------------\n", .{});
    std.debug.warn("{}", .{request});
    try writer.write(request);
}

const HttpResponseData = struct {
    headerLimit: usize,
    dataLimit: usize,
};
pub fn readHttpResponse(buffer: []u8, reader: *Reader) !HttpResponseData {
    var totalRead : usize = 0;
    while (true) {
        if (totalRead >= buffer.len)
            return error.HttpResponseHeaderTooBig;
        var len = try reader.read(buffer[totalRead..]);
        if (len == 0) return error.HttpResponseIncomplete;
        var headerLimit = totalRead;
        totalRead = totalRead + len;
        if (headerLimit <= 3)
            headerLimit += 3;
        while (headerLimit < totalRead) {
            headerLimit += 1;
            if (ziget.mem.cmp(u8, buffer[headerLimit - 4..].ptr, "\r\n\r\n", 4))
                return HttpResponseData { .headerLimit = headerLimit, .dataLimit = totalRead };
        }
    }
}

// TODO: call sendFile on linux so we don't have to read the data into memory
pub fn forward(buffer: []u8, reader: *Reader, writer: *Writer) !void {
    while (true) {
        var len = try reader.read(buffer);
        if (len == 0) break;
        try writer.write(buffer[0..len]);
    }
}

pub fn downloadHttpOrRedirect(options: *DownloadOptions, httpUrl: Url.Http, writer: *Writer) !DownloadResult {
    const file = try net.tcpConnectToHost(options.allocator, httpUrl.getHostString(), httpUrl.getPortOrDefault());
    defer {
        // TODO: file.shutdown()???
        file.close();
    }
    var fileRw = FileReaderWriter.init(file);
    var rw = &fileRw.rw;

    var sslConn : ssl.SslConn = undefined;
    if (httpUrl.secure) {
        sslConn = try ssl.SslConn.init(file, httpUrl.getHostString());
        rw = &sslConn.rw;
    }
    defer { if (httpUrl.secure) sslConn.deinit(); }

    try sendHttpGet(options.allocator, &rw.writer, httpUrl, false);
    const buffer = options.buffer;
    const response = try readHttpResponse(buffer, &rw.reader);
    std.debug.warn("--------------------------------------------------------------------------------\n", .{});
    std.debug.warn("Received Http Response:\n", .{});
    std.debug.warn("--------------------------------------------------------------------------------\n", .{});
    std.debug.warn("{}", .{buffer[0..response.headerLimit]});
    const httpResponse = buffer[0..response.headerLimit];
    {
        const status = try http.parse.parseHttpStatusLine(httpResponse);
        if (status.code != 200) {
            const headers = buffer[status.len..];
            if (status.code == 301) {
                // TODO: create copy of location url
                const location = (try http.parse.parseHeaderValue(headers, "Location")) orelse
                    return error.HttpRedirectNoLocation;
                return DownloadResult { .Redirect = try ziget.url.parseUrl(location) };
            }
            std.debug.warn("Non 200 status code: {} {}\n", .{status.code, status.getMsg(httpResponse)});
            return error.HttpNon200StatusCode;
        }
    }

    if (response.dataLimit > response.headerLimit) {
        try writer.write(buffer[response.headerLimit..response.dataLimit]);
    }
    try forward(buffer, &rw.reader, writer);
    return DownloadResult.Success;
}
