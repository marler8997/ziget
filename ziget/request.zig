const std = @import("std");
const mem = std.mem;
const net = std.net;

const Allocator = mem.Allocator;

const urlmod = @import("./url.zig");
const UrlScheme = urlmod.UrlScheme;
const Url = urlmod.Url;

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

// NOTE: linux supports sending data between files without loading it into userspace memory
pub fn readHttpToFile(buffer: []u8, inFile: std.fs.File, outFile: std.fs.File) !void {
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
    var buffer: [1024]u8 = undefined; // TODO: this is temporary
    try readHttpToFile(&buffer, file, std.io.getStdOut());
}

