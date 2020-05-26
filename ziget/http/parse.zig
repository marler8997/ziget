/// Simple Temporary Code to Parse HTTP
const std = @import("std");
const testing = std.testing;

const ziget = @import("../../ziget.zig");

pub const HttpStatusLineResult = struct {
    len: u16,
    code: u16,
    msgOffset: u16,
    msgLimit: u16,
    pub fn getMsg(self: HttpStatusLineResult, data: []const u8) []const u8 {
        return data[self.msgOffset..self.msgLimit];
    }
};
pub fn parseHttpStatusLine(data: []const u8) !HttpStatusLineResult {
    var offset : u16 = 0;
    while (true) : (offset += 1) {
        if (offset >= data.len) return error.HttpStatusLineMissingFirstSpace;
        if (data[offset] == ' ') break;
    }
    offset += 1;
    var code : u16 = 0;
    var msgOffset : u16 = 0;
    parseMsg: {
        parseCode: {while (true) : (offset += 1) {
            if (offset >= data.len) return error.HttpStatusEndedAtCode;
            const c = data[offset];
            if (c >= '0' and c <= '9') {
                code *= 10;
                code += (c - '0');
                if (code > 999) return error.HttpStatusCodeTooBig;
            } else if (c == ' ') {
                break :parseCode;
            } else if (c == '\r') {
                msgOffset = offset;
                break :parseMsg;
            } else return error.HttpStatusInavlidCodeChar;
        }}
        offset += 1;
        msgOffset = offset;
        while (true) : (offset += 1) {
            if (offset >= data.len) return error.HttpStatusEndedAtMsg;
            if (data[offset] == '\r') break :parseMsg;
        }
    }
    const msgLimit = offset;
    std.debug.assert(data[offset] == '\r');
    offset += 1;
    if (offset >= data.len) return error.HttpStatusEndedAtCarriageReturn;
    if (data[offset] != '\n') return error.HttpStatusNoLineFeedAfterCarriageReturn;
    offset += 1;
    return HttpStatusLineResult { .len = offset, .code = code, .msgOffset = msgOffset, .msgLimit = msgLimit };
}

fn testStatusLine(str: []const u8, code: u16, msg: []const u8) !void {
    const result = try parseHttpStatusLine(str);
    testing.expect(result.len == str.len);
    testing.expect(result.code == code);
    testing.expect(std.mem.eql(u8, result.getMsg(str), msg));
}
test "parseHttpStatusLine" {
    try testStatusLine("HTTP/1.1 200 OK\r\n", 200, "OK");
    try testStatusLine("HTTP/1.1 301 Moved Permanently\r\n", 301, "Moved Permanently");
    try testStatusLine("HTTP/1.1 501 Not Implemented\r\n", 501, "Not Implemented");

    testing.expectError(error.HttpStatusLineMissingFirstSpace, parseHttpStatusLine(""));
    testing.expectError(error.HttpStatusLineMissingFirstSpace, parseHttpStatusLine("H"));
    testing.expectError(error.HttpStatusEndedAtCode, parseHttpStatusLine("HTTP/1.1 "));
    testing.expectError(error.HttpStatusEndedAtCode, parseHttpStatusLine("HTTP/1.1 2"));
    testing.expectError(error.HttpStatusEndedAtCode, parseHttpStatusLine("HTTP/1.1 20"));
    testing.expectError(error.HttpStatusEndedAtCode, parseHttpStatusLine("HTTP/1.1 200"));
    testing.expectError(error.HttpStatusEndedAtMsg, parseHttpStatusLine("HTTP/1.1 200 "));
    testing.expectError(error.HttpStatusEndedAtCarriageReturn, parseHttpStatusLine("HTTP/1.1 200 \r"));
    testing.expectError(error.HttpStatusNoLineFeedAfterCarriageReturn, parseHttpStatusLine("HTTP/1.1 200 \r "));
}

fn toHeaderNewline(data: []const u8, offset: usize) error{HttpHeaderNoNewline}!usize {
    var end = offset;
    while (true) : (end += 1) {
        if (end + 1 >= data.len) return error.HttpHeaderNoNewline;
        if (data[end] == '\r' and data[end + 1] == '\n')
            return end;
    }
}

pub fn parseHeaderValue(data: []const u8, headerName: []const u8) !?[]const u8 {
    var offset: usize = 0;
    while (true) {
        if (offset + headerName.len + 3 > data.len)
            return null;
        if (ziget.mem.cmp(u8, data.ptr + offset, headerName.ptr, headerName.len) and data[offset + headerName.len] == ':') {
            offset += headerName.len + 1;
            while (true) : (offset += 1) {
                if (offset >= data.len) return error.HttpHeaderNoNewline;
                if (data[offset] != ' ' and data[offset] != '\t') break;
            }
            return data[offset .. try toHeaderNewline(data, offset)];
        }
        offset = (try toHeaderNewline(data, offset)) + 2;
    }
    return data;
}

test "parseHeaderValue" {
    testing.expect(std.mem.eql(u8, "Bar", (try parseHeaderValue("Foo: Bar\r\n", "Foo")).?));
    testing.expect(std.mem.eql(u8, "Bar", (try parseHeaderValue("A:\r\nB:  \r\nFoo: Bar\r\n", "Foo")).?));
    testing.expect(null == try parseHeaderValue("A:\r\nB:  \r\nFoo: Bar\r\n", "Foo2"));
}
