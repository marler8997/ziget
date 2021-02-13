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
    const zig = "zig";
    const ziget = "." ++ sep ++ "zig-cache" ++ sep ++ "bin" ++ sep ++ "ziget";

    const tests = [_]Test {
        Test.init(&[_][]const u8 { zig, "build"}),
        Test.init(&[_][]const u8 { ziget, "google.com"}),
        Test.init(&[_][]const u8 { ziget, "http://google.com"}),
        Test.init(&[_][]const u8 { zig, "build", "-Dopenssl"}),
        Test.init(&[_][]const u8 { ziget, "http://google.com"}),
        Test.init(&[_][]const u8 { ziget, "http://ziglang.org"}),
    };

    for (tests) |t| {
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
    std.debug.print("[test] Sucess\n", .{});
    return 0;
}
