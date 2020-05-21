/// NOTE: This module was implemented quickly to get functionality, not designed
///       to handle all cases from the beginning.  It is likely to change quite a bit.
const std = @import("std");

//pub const UrlScheme = enum {
//    none,
//    unknown,
//    http,
//    https,
//};

pub const Url = union(enum) {
    None: void,
    Unknown: struct {
        str: [*]const u8,
    },
    Http: Http,
    Https: void, // not impl

    pub const Http = struct {
        str: []const u8,
        hostOffset: u8,
        hostLimit: u16,
        port: ?u16,
        pathOffset: u16,
        pathLimit: u16,
        queryOffset: u16,
        pub fn getHostString(self: @This()) []const u8 {
            return self.str[self.hostOffset..self.hostLimit];
        }
        pub fn getHostPortString(self: @This()) []const u8 {
            return self.str[self.hostOffset..self.pathOffset];
        }
        pub fn getPathString(self: @This()) []const u8 {
            if (self.pathOffset == 0) return "";
            return self.str[self.pathOffset..self.pathLimit];
        }
    };

    pub fn hostString(self: @This()) []const u8 {
        switch (self.scheme) {
            .none => @panic("no scheme not implemented"),
            .unknown => @panic("unknown scheme has no host"),
            //. => @panic("no scheme not implemented"),
            //.none => @panic("no scheme not implemented"),
        }
    }

    pub fn schemeString(self: @This()) []const u8 {
        return switch (self) {
            .None => |u| "",
            .Unknown => |u| u.str[0..ptrIndexOf(u8, u.str, ':')],
            .Http => |u| "http",
            .Https => |u| "https",
        };
    }
};


pub fn ptrIndexOf(comptime T: type, haystack: [*]const T, needle: T) usize {
    var i: usize = 0;
    while (true) : (i += 1) {
        if (haystack[i] == needle) return i;
    }
}

pub fn parseUrl(url: []const u8) !Url {
    return parseUrlLimit(url.ptr, url.ptr + url.len);
}

pub fn eqlPtr(comptime T: type, a: [*]const T, b: [*]const T, len: usize) bool {
    if (a == b) return true;
    for (a[0..len]) |item, index| {
        if (b[index] != item) return false;
    }
    return true;
}


fn startsWith(ptr: [*]const u8, needle: []const u8) bool {
    return (@ptrToInt(limit) - @ptrToInt(ptr) >= needle.len) and
        std.mem.startsWith(u8, ptr, needle);
}


fn matchSkip(ptrRef: *[*]const u8, limit: [*]const u8, needle: []const u8) bool {
    if ( (@ptrToInt(limit) - @ptrToInt(ptrRef.*) >= needle.len) and
        eqlPtr(u8, ptrRef.*, needle.ptr, needle.len)
    ) {
        ptrRef.* = @intToPtr([*]const u8, @ptrToInt(ptrRef.*) + needle.len);
        return true;
    }
    return false;
}

// a temporary implementation
pub fn parseUrlLimit(start: [*]const u8, limit: [*]const u8) !Url {
    var ptr = start;
    if (matchSkip(&ptr, limit, "http://")) {
        if (ptr == limit) return error.UrlHttpMissingHost;
        var hostStart = ptr;
        var hostLimit : [*]const u8 = undefined;
        var port : ?u16 = null;
        parsePort: {
            parseHost: {
                while (true) {
                    ptr += 1;
                    if (ptr == limit) {
                        hostLimit = ptr;
                        break :parsePort;
                    }
                    if (ptr[0] == '@') {
                        @panic("userinfo not implemented");
                    }
                    if (ptr[0] == '/') {
                        hostLimit = ptr;
                        break :parsePort;
                    }
                    if (ptr[0] == ':') {
                        hostLimit = ptr;
                        break :parseHost;
                    }
                }
            }
            std.debug.assert(ptr[0] == ':');
            ptr += 1;
            if (ptr == limit) return error.UrlEndedAtPortColon;
            var portStart = ptr;
            var port32 : u32 = 0;
            while (true) {
                ptr += 1;
                if (ptr == limit or ptr[0] == '/')
                    break;
                if (ptr[0] > '9' or ptr[0] < '0')
                    return error.UrlInvalidPortCharacter;
                port32 *= 10;
                port32 += ptr[0] - '0';
                if (port32 >= 65535) return error.UrlPortTooHigh;
            }
            port = @intCast(u16, port32);
        }
        var pathOffset : u16 = undefined;
        var pathLimit : u16 = undefined;
        if (ptr == limit) {
            pathOffset = @intCast(u16, @ptrToInt(ptr) - @ptrToInt(start));
            pathLimit  = pathOffset;
        } else {
            std.debug.assert(ptr[0] == '/');
            ptr += 1;
            pathOffset = @intCast(u16, @ptrToInt(ptr) - @ptrToInt(start));
            // TODO: this won't be correct if there is a query
            pathLimit  = @intCast(u16, @ptrToInt(limit) - @ptrToInt(start));
        }
        return Url { .Http = .{
            .str = start[0..@ptrToInt(limit) - @ptrToInt(start)],
            .hostOffset  = @intCast(u8 , @ptrToInt(hostStart) - @ptrToInt(start)),
            .hostLimit   = @intCast(u16, @ptrToInt(hostLimit) - @ptrToInt(start)),
            .port        = port,
            .pathOffset  = pathOffset,
            .pathLimit   = pathLimit,
            .queryOffset = 0,
        }};
    } else {
        @panic("unknown scheme not impl");
    }
//    const scheme = schemeInit: {
//        if (matchSkip(&ptr, limit, "http://")) {
//            break :schemeInit UrlScheme.http;
//        } else {
//            @panic("unknown scheme not impl");
//        }
//    };
//    
    @panic("url not impl");
}

