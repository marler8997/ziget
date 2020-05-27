const std = @import("std");
pub const mem = @import("./ziget/mem.zig");
pub const url = @import("./ziget/url.zig");
pub const request = @import("./ziget/request.zig");
pub const http = @import("./ziget/http.zig");
pub const readwrite = @import("./ziget/readwrite.zig");

test "" {
    std.meta.refAllDecls(@This());
}
