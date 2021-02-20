const std = @import("std");
const sep = std.fs.path.sep_str;

const Test = struct {
    cmd: []const []const u8,
    pub fn init(cmd: []const []const u8) Test {
        return .{ .cmd = cmd };
    }
};

pub fn runGetOutputArray(allocator: *std.mem.Allocator, argv: []const []const u8) !std.ChildProcess.ExecResult {
    return std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = null,
        .env_map = null,
        .max_output_bytes = std.math.maxInt(usize),
        .expand_arg0 = .no_expand,
    }) catch |err|{
        std.log.err("failed to execute '{s}': {}", .{argv[0], err});
        return error.SubProcessFailed;
    };
}

pub fn main() !u8 {
    var nossl = false;
    var openssl = false;
    var iguana = false;
    var bearssl = false;
    var schannel = false;

    var args = try std.process.argsAlloc(std.heap.page_allocator);
    args = args[1..];
    if (args.len != 1) {
        std.log.err("please provide a test to run\n", .{});
        return 1;
    }

    {
        const test_name = args[0];
        if (std.mem.eql(u8, test_name, "nossl")) {
            nossl = true;
        } else if (std.mem.eql(u8, test_name, "openssl")) {
            openssl = true;
        } else if (std.mem.eql(u8, test_name, "iguana")) {
            iguana = true;
        } else if (std.mem.eql(u8, test_name, "bearssl")) {
            bearssl = true;
        } else if (std.mem.eql(u8, test_name, "schannel")) {
            schannel = true;
        } else {
            std.log.err("unknown test '{s}'\n", .{test_name});
            return 1;
        }
    }

    const zig = "zig";
    const ziget = exeFile("." ++ sep ++ "zig-cache" ++ sep ++ "bin" ++ sep ++ "ziget");

    var tests = std.ArrayList(Test).init(std.heap.page_allocator);
    defer tests.deinit();

    if (nossl) {
        try tests.append(Test.init(&[_][]const u8 { zig, "build"}));
        try tests.append(Test.init(&[_][]const u8 { ziget, "google.com"}));
        try tests.append(Test.init(&[_][]const u8 { ziget, "http://google.com"}));
    }
    if (openssl) {
        try tests.append(Test.init(&[_][]const u8 { zig, "build", "-Dopenssl"}));
        try tests.append(Test.init(&[_][]const u8 { ziget, "http://google.com"}));
        try tests.append(Test.init(&[_][]const u8 { ziget, "http://ziglang.org"}));
    }
    if (iguana) {
        try tests.append(Test.init(&[_][]const u8 { zig, "build", "-Diguana"}));
        try tests.append(Test.init(&[_][]const u8 { ziget, "http://google.com"}));
        try tests.append(Test.init(&[_][]const u8 { ziget, "http://ziglang.org"}));
    }
    if (bearssl) {
        try tests.append(Test.init(&[_][]const u8 { zig, "build", "-Dbearssl"}));
        try tests.append(Test.init(&[_][]const u8 { ziget, "http://google.com"}));
        try tests.append(Test.init(&[_][]const u8 { ziget, "http://ziglang.org"}));
    }
    if (schannel) {
        try tests.append(Test.init(&[_][]const u8 { zig, "build", "-Dschannel"}));
        try tests.append(Test.init(&[_][]const u8 { ziget, "http://google.com"}));
        try tests.append(Test.init(&[_][]const u8 { ziget, "http://ziglang.org"}));
    }

    for (tests.items) |t| {
        std.debug.print("[test] Executing '{s}'\n", .{t.cmd});
        const result = try runGetOutputArray(std.testing.allocator, t.cmd);
        if (result.stdout.len == 0) {
            std.debug.print("[test] STDOUT: none\n", .{});
        } else {
            std.debug.print("[test] --------------------------------------------------------------------------------\n", .{});
            std.debug.print("[test] STDOUT\n", .{});
            std.debug.print("[test] --------------------------------------------------------------------------------\n", .{});
            std.debug.print("{s}\n", .{result.stdout});
        }
        if (result.stderr.len == 0) {
            std.debug.print("[test] STDERR: none\n", .{});
        } else {
            std.debug.print("[test] --------------------------------------------------------------------------------\n", .{});
            std.debug.print("[test] STDERR\n", .{});
            std.debug.print("[test] --------------------------------------------------------------------------------\n", .{});
            std.debug.print("{s}\n", .{result.stderr});
        }
        switch (result.term) {
            .Exited => |c| {
                if (c != 0) {
                    return 1;
                }
            },
            else => return 1,
        }
    }
    std.debug.print("[test] Success\n", .{});
    return 0;
}

fn exeFile(comptime s: []const u8) []const u8 {
    if (std.builtin.os.tag == .windows) return s ++ ".exe";
    return s;
}
