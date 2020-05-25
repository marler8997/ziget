const std = @import("std");
const mem = std.mem;
const net = std.net;

const Allocator = mem.Allocator;

const urlmod = @import("./url.zig");
const UrlScheme = urlmod.UrlScheme;
const Url = urlmod.Url;

const ziget = @import("../ziget.zig");

pub fn download(allocator: *Allocator, url: Url) !void {
    switch (url) {
        .None => @panic("no scheme not implemented"),
        .Unknown => return error.UnknownUrlScheme,
        .Http => |httpUrl| return downloadHttp(allocator, httpUrl),
        .Https => |httpsUrl| @panic("https not impl"),
    }
}

pub fn httpAlloc(allocator: *Allocator, method: []const u8, resource: []const u8, host: []const u8,headers: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator,
           "{} {} HTTP/1.1\r\n"
        ++ "Host: {}\r\n"
        ++ "{}"
        ++ "\r\n", .{
        method, resource, host, headers});
}

pub fn sendHttpGet(allocator: *Allocator, file: std.fs.File, httpUrl: Url.Http, keepAlive: bool) !void {
    const request = try httpAlloc(allocator, "GET", httpUrl.str,
        httpUrl.getHostPortString(),
        if (keepAlive) "Connection: keep-alive\r\n" else "Connection: close\r\n"
    );
    defer allocator.free(request);
    std.debug.warn("--------------------------------------------------------------------------------\n", .{});
    std.debug.warn("{}", .{request});
    std.debug.warn("--------------------------------------------------------------------------------\n", .{});
    try file.writeAll(request);
}

const HttpResponseData = struct {
    headerLimit: usize,
    dataLimit: usize,
};
pub fn readHttpResponse(buffer: []u8, inFile: std.fs.File) !HttpResponseData {
    var totalRead : usize = 0;
    while (true) {
        if (totalRead >= buffer.len)
            return error.HttpResponseHeaderTooBig;
        var len = try inFile.read(buffer[totalRead..]);
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
pub fn forward(buffer: []u8, inFile: std.fs.File, outFile: std.fs.File) !void {
    while (true) {
        var len = try inFile.read(buffer);
        if (len == 0) break;
        try outFile.writeAll(buffer[0..len]);
    }
}

pub fn downloadHttp(allocator: *Allocator, httpUrl: Url.Http) !void {
    const file = try net.tcpConnectToHost(allocator, httpUrl.getHostString(), httpUrl.port orelse 80);
    defer file.close();

    try sendHttpGet(allocator, file, httpUrl, false);
    var buffer = try allocator.alloc(u8, 4096); // max 4K HTTP response header for now?
    defer allocator.free(buffer);
    const response = try readHttpResponse(buffer, file);
    std.debug.warn("HTTP Response:\n", .{});
    std.debug.warn("--------------------------------------------------------------------------------\n", .{});
    std.debug.warn("{}", .{buffer[0..response.headerLimit]});
    std.debug.warn("--------------------------------------------------------------------------------\n", .{});
    if (response.dataLimit > response.headerLimit) {
        try std.io.getStdOut().writeAll(buffer[response.headerLimit..response.dataLimit]);
    }
    try forward(buffer, file, std.io.getStdOut());
}

