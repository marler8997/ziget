const std = @import("std");
const testing = std.testing;

const CharacterFlags = struct {
    pub const none      = 0;
    pub const ctl       = 1 << 0;
    pub const separator = 1 << 1;
    pub const ctl_separator = ctl | separator;
};
const characterFlagTable = [127]u8 {
    CharacterFlags.ctl,            // '\0'
    CharacterFlags.ctl,            // '\x01'
    CharacterFlags.ctl,            // '\x02'
    CharacterFlags.ctl,            // '\x03'
    CharacterFlags.ctl,            // '\x04'
    CharacterFlags.ctl,            // '\x05'
    CharacterFlags.ctl,            // '\x06'
    CharacterFlags.ctl,            // '\x07'
    CharacterFlags.ctl,            // '\x08'
    CharacterFlags.ctl_separator,  // '\t'
    CharacterFlags.ctl,            // '\n'
    CharacterFlags.ctl,            // '\x0B'
    CharacterFlags.ctl,            // '\x0C'
    CharacterFlags.ctl,            // '\r'
    CharacterFlags.ctl,            // '\x0E'
    CharacterFlags.ctl,            // '\x0F'
    CharacterFlags.ctl,            // '\x11'
    CharacterFlags.ctl,            // '\x12'
    CharacterFlags.ctl,            // '\x13'
    CharacterFlags.ctl,            // '\x14'
    CharacterFlags.ctl,            // '\x15'
    CharacterFlags.ctl,            // '\x16'
    CharacterFlags.ctl,            // '\x17'
    CharacterFlags.ctl,            // '\x18'
    CharacterFlags.ctl,            // '\x19'
    CharacterFlags.ctl,            // '\x1A'
    CharacterFlags.ctl,            // '\x1B'
    CharacterFlags.ctl,            // '\x1C'
    CharacterFlags.ctl,            // '\x1D'
    CharacterFlags.ctl,            // '\x1E'
    CharacterFlags.ctl,            // '\x1F'
    CharacterFlags.separator,      // ' '
    CharacterFlags.none,           // '!'
    CharacterFlags.separator,      // '"'
    CharacterFlags.none,           // '#'
    CharacterFlags.none,           // '$'
    CharacterFlags.none,           // '%'
    CharacterFlags.none,           // '&'
    CharacterFlags.none,           // '\''
    CharacterFlags.separator,      // '('
    CharacterFlags.separator,      // ')'
    CharacterFlags.none,           // '*'
    CharacterFlags.none,           // '+'
    CharacterFlags.separator,      // ','
    CharacterFlags.none,           // '-'
    CharacterFlags.none,           // '.'
    CharacterFlags.separator,      // '/'
    CharacterFlags.none,           // '0'
    CharacterFlags.none,           // '1'
    CharacterFlags.none,           // '2'
    CharacterFlags.none,           // '3'
    CharacterFlags.none,           // '4'
    CharacterFlags.none,           // '5'
    CharacterFlags.none,           // '6'
    CharacterFlags.none,           // '7'
    CharacterFlags.none,           // '8'
    CharacterFlags.none,           // '9'
    CharacterFlags.separator,      // ':'
    CharacterFlags.separator,      // ';'
    CharacterFlags.separator,      // '<'
    CharacterFlags.separator,      // '='
    CharacterFlags.separator,      // '>'
    CharacterFlags.separator,      // '?'
    CharacterFlags.separator,      // '@'
    CharacterFlags.none,           // 'A'
    CharacterFlags.none,           // 'B'
    CharacterFlags.none,           // 'C'
    CharacterFlags.none,           // 'D'
    CharacterFlags.none,           // 'E'
    CharacterFlags.none,           // 'F'
    CharacterFlags.none,           // 'G'
    CharacterFlags.none,           // 'H'
    CharacterFlags.none,           // 'I'
    CharacterFlags.none,           // 'J'
    CharacterFlags.none,           // 'K'
    CharacterFlags.none,           // 'L'
    CharacterFlags.none,           // 'M'
    CharacterFlags.none,           // 'N'
    CharacterFlags.none,           // 'O'
    CharacterFlags.none,           // 'P'
    CharacterFlags.none,           // 'Q'
    CharacterFlags.none,           // 'R'
    CharacterFlags.none,           // 'S'
    CharacterFlags.none,           // 'T'
    CharacterFlags.none,           // 'U'
    CharacterFlags.none,           // 'V'
    CharacterFlags.none,           // 'W'
    CharacterFlags.none,           // 'X'
    CharacterFlags.none,           // 'Y'
    CharacterFlags.none,           // 'Z'
    CharacterFlags.separator,      // '['
    CharacterFlags.separator,      // '\\'
    CharacterFlags.separator,      // ']'
    CharacterFlags.none,           // '^'
    CharacterFlags.none,           // '_'
    CharacterFlags.none,           // '`'
    CharacterFlags.none,           // 'a'
    CharacterFlags.none,           // 'b'
    CharacterFlags.none,           // 'c'
    CharacterFlags.none,           // 'd'
    CharacterFlags.none,           // 'e'
    CharacterFlags.none,           // 'f'
    CharacterFlags.none,           // 'g'
    CharacterFlags.none,           // 'h'
    CharacterFlags.none,           // 'i'
    CharacterFlags.none,           // 'j'
    CharacterFlags.none,           // 'k'
    CharacterFlags.none,           // 'l'
    CharacterFlags.none,           // 'm'
    CharacterFlags.none,           // 'n'
    CharacterFlags.none,           // 'o'
    CharacterFlags.none,           // 'p'
    CharacterFlags.none,           // 'q'
    CharacterFlags.none,           // 'r'
    CharacterFlags.none,           // 's'
    CharacterFlags.none,           // 't'
    CharacterFlags.none,           // 'u'
    CharacterFlags.none,           // 'v'
    CharacterFlags.none,           // 'w'
    CharacterFlags.none,           // 'x'
    CharacterFlags.none,           // 'y'
    CharacterFlags.none,           // 'z'
    CharacterFlags.separator,      // '{'
    CharacterFlags.none,           // '|'
    CharacterFlags.separator,      // '}'
    CharacterFlags.none,           // '~'
    CharacterFlags.none,           // '\x7F'
};
fn getCharacterFlags(c: u8) u8 {
    return if (c < characterFlagTable.len) characterFlagTable[c] else CharacterFlags.ctl;
}
fn validTokenChar(c: u8) bool {
    return 0 == (getCharacterFlags(c) & CharacterFlags.ctl_separator);
}


pub const HttpParseErrorPartial = error {
    InvalidMethodCharacter,
    MethodNameTooLong,
    BadVersionNewline,
    BadHttpVersion,
    InvalidHeaderNameCharacter,
    HeaderNameTooLong,
};
pub const HttpParseErrorComplete = error {
    InvalidMethodCharacter,
    MethodNameTooLong,
    BadVersionNewline,
    BadHttpVersion,
    InvalidHeaderNameCharacter,
    HeaderNameTooLong,
    Incomplete,
};

const HeaderValueStave = enum {
    noNewline, carriageReturn, lineFeed,
};

pub const HttpParserOptions = struct {
    partialData: bool,
    maxMethodLen: comptime_int,
    onMethod: fn(data: []const u8) void,
    onUri: fn(data: []const u8) void,
    // TODO: fix this
    onPartial: fn(data: []const u8) void,
};

pub fn HttpParserGeneric(comptime options_: HttpParserOptions) type { return struct {

    pub const options = options_;
    pub const Error = if (options.partialData)
        HttpParseErrorPartial else HttpParseErrorComplete;
    const Self = @This();

    const State = enum {
        method,
        uri,
        versionAndNewline,
        headerName,
    };
    state: State,
    stateData: union {
        offset32: u32,
    },

    // TODO: this could be replaced with an enum that is used as a function-pointer index
    //       or it could just be inside a big switch
    //nextParse: fn(self: *Self, buffer: []u8) void,

    pub fn init() Self {
        return Self { .state = State.method, .stateData = undefined };
    }
    //pub fn reset(self: *Self) void {
    //    self.state = State.method;
    //    self.offset = 0;
    //}

    fn parse(self: *Self, data: []const u8) !void {
        var remaining = data;
        while (remaining.len > 0) {
            const method = switch (self.state) {
                .method => parseMethod,
                .uri => parseUri,
                .versionAndNewline => parseVersionAndNewline,
                .headerName => @panic("headerName not impl"),
            };
            const parsedLen = try method(self, remaining);
            std.debug.assert(parsedLen > 0);
            remaining = remaining[parsedLen..];
        }
    }
    fn parseMethod(self: *Self, data: []const u8) Error!usize {
        for (data) |c, i| {
            if (c == ' ') {
                options.onMethod(data[0..i]);
                self.state = .uri;
                return i + 1;
            }
            if (!validTokenChar(c))
                return Error.InvalidMethodCharacter;
            if (i >= options.maxMethodLen)
                return Error.MethodNameTooLong;
        }
        if (comptime options.partialData) {
            //options.onMethodPartial(self.state, data);
            options.onPartial(data);
            return data.len;
        }
        return Error.Incomplete;
    }
    /// grammar here: https://tools.ietf.org/html/rfc3986#section-3
    ///     URI       = [ scheme ":" hier-part ] [ "?" query ] [ "#" fragment ]
    ///     hier-part = "//" authority path-abempty
    ///               / path-absolute
    ///               / path-rootless
    ///               / path-empty
    fn parseUri(self: *Self, data: []const u8) Error!usize {
        for (data) |c, i| {
            if (c == ' ') {
                options.onUri(data[0..i]);
                self.state = .versionAndNewline;
                self.stateData = .{ .offset32 = 0 };
                return i + 1;
            }
            // TODO: check if there is a maximum URI and/or if the URI character is valid
        }
        if (comptime options.partialData) {
            //options.onUriPartial(self.state, data);
            options.onPartial(data);
            return data.len;
        }
        return Error.Incomplete;
    }

    const HTTP_VERSION_AND_NEWLINE = "HTTP/1.1\r\n";
    fn parseVersionAndNewline(self: *Self, data: []const u8) Error!usize {
        const needed = HTTP_VERSION_AND_NEWLINE.len - self.stateData.offset32;
        if (data.len < needed) {
            if (!std.mem.eql(u8, HTTP_VERSION_AND_NEWLINE[self.stateData.offset32..], data[0..needed]))
                return error.BadVersionNewline;
            self.stateData.offset32 += @intCast(u32, data.len);
            return data.len;
        }

        if (!std.mem.eql(u8, HTTP_VERSION_AND_NEWLINE[self.stateData.offset32..], data[0..needed]))
            return error.BadVersionNewline;
        self.state = .headerName;
        return needed;
    }
};}



fn testOnAnything(data: []const u8) void {
    std.debug.warn("test got data '{}'\n", .{data});
}
test "HttpParser" {
    inline for ([2]bool {false, true}) |partialData| {
        testParser(HttpParserGeneric(HttpParserOptions {
            .partialData = partialData,
            .maxMethodLen = 30,
            .onMethod = testOnAnything,
            .onUri = testOnAnything,
            .onPartial = testOnAnything,
        }));
    }
}

fn testParser(comptime HttpParser: type) void {
    {var c : u8 = 0; while (c < 0x7f) : (c += 1) {
        if (validTokenChar(c) or c == ' ')
            continue;
        {
            var parser = HttpParser.init();
            var buf = [_]u8 {c, ' '};
            testing.expectError(HttpParser.Error.InvalidMethodCharacter, parser.parse(&buf));
        }
        {
            var parser = HttpParser.init();
            var buf = [_]u8 {'G','E','T',c, ' '};
            testing.expectError(HttpParser.Error.InvalidMethodCharacter, parser.parse(&buf));
        }
    }}
    {
        var parser = HttpParser.init();
        var buf: [HttpParser.options.maxMethodLen + 1]u8 = undefined;
        std.mem.set(u8, &buf, 'A');
        testing.expectError(HttpParser.Error.MethodNameTooLong, parser.parse(&buf));
    }
    for ([_][]const u8 {
        "GET / HTTP/1.1\r\r",
        "GET / HTTP/1.0\r\n",
        "GET / !TTP/1.1\r\n",
    }) |buf| {
        var parser = HttpParser.init();
        testing.expectError(HttpParser.Error.BadVersionNewline, parser.parse(buf));
    }
}