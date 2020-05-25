





//pub fn Parser() type {
//    return struct {
//        const Transition = struct {
//           
//        }
//        
//        const Node = struct {
//        };
//        
//        const httpParser = [_]Node {
//            Node { },
//            Node { },
//        };
//    };
//}
//



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


pub fn Transition(comptime T: type) type { return struct {
    t: T,
    state: comptime_int,
};}

const State = struct {
    TokenSet: type,
    //identifier: fn(u8) T,
    transitions: []const Transition(u8),
};

pub fn State2(comptime T: type) type { return struct {
    identifier: fn(u8) T,
};}

const Parser = struct {
    //states: []const State,
    states: var,
    // Note: should I enforce comptime here?
    pub fn parse(comptime self: Parser, str: []const u8) void {
        //var state = 0;
        //while (true) {
        //}
    }
};

const httpParser = Parser {
    .states = .{0, 1},
//        State2(enum { Space }) {
//        },
//        State2(enum { Space }) {
//        },
//    },
};

//const httpParser = Parser {
//    .states = &[_]State {
//        // 0: Method
//        .{
//            .TokenSet = enum { Space },
//            .transitions = &([_]Transition {
//                .{ .c = ' ', .state = 1 },
//            }),
//        },
//        // 1: Uri
//        .{
//            .transitions = &[_]Transition {
//                .{ .c = ' ', .state = 2 },
//            },
//        },
//        // 2: Version
//        .{
//            .transitions = &[_]Transition {
//                .{ .c = '\n', .state = 3 },
//            },
//        },
//        // 3: HeaderOrEnd
//        .{
//            .transitions = &[_]Transition {
//                .{ .c = '\r', .state = 5 },
//                .{ .c = ':', .state = 4 },
//            },
//        },
//        // 3: HeaderName
//        .{
//            .transitions = &[_]Transition {
//                .{ .c = '\n', .state = 5 },
//                .{ .c = ':', .state = 4 },
//            },
//        },
//        // 4: HeaderValue
//        .{
//            .transitions = &[_]Transition {
//                .{ .c = '\n', .state = 4 },
//            },
//        },
//        // 5: done
//        .{
//            .transitions = &[_]Transition {
//            },
//        },
//    },
//};
//

test "http" {
    httpParser.parse("hello");
    
}
