const std = @import("std");
const builtin = @import("builtin");

const ziget = @import("ziget");

// disable debug logging by default
pub const log_level = switch (builtin.mode) {
    .Debug => .info,
    else => std.log.default_level,
};

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

fn printError(comptime fmt: []const u8, args: anytype) void {
  std.debug.print("Error: " ++ fmt ++ "\n", args);
}

fn usage() void {
    std.debug.print(
      \\Usage: ziget [-options] <url>
      \\Options:
      \\  --out <file>         download to given file instead of url basename
      \\  --stdout             download to stdout
      \\  --max-redirs <num>   maximum number of redirects, default is 50
      \\
      , .{});
}

fn getArgOption(args: [][]const u8, i: *usize) []const u8 {
    i.* = i.* + 1;
    if (i.* >= args.len) {
        printError("option {s} requires an argument", .{args[i.* - 1]});
        std.os.exit(1);
    }
    return args[i.*];
}

pub fn main() anyerror!u8 {
    var args = try std.process.argsAlloc(allocator);
    if (args.len <= 1) {
      usage();
      return 1; // error exit code
    }
    args = args[1..];

    var outFilenameOption : ?[]const u8 = null;
    var downloadToStdout = false;
    var maxRedirects : u16 = 50;
    {
        var newArgsLength : usize = 0;
        defer args.len = newArgsLength;
        var i : usize = 0;
        while (i < args.len) : (i += 1) {
            var arg = args[i];
            if (!std.mem.startsWith(u8, arg, "-")) {
                args[newArgsLength] = arg;
                newArgsLength += 1;
            } else if (std.mem.eql(u8, arg, "--out")) {
                outFilenameOption = getArgOption(args, &i);
            } else if (std.mem.eql(u8, arg, "--stdout")) {
                downloadToStdout = true;
            } else if (std.mem.eql(u8, arg, "--max-redirs")) {
                @panic("--max-redirs not implemented");
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                usage();
                return 1;
            } else {
                printError("unknown option '{s}'", .{arg});
                return 1;
            }
        }
    }

    if (args.len != 1) {
        printError("expected 1 URL but got {} arguments", .{args.len});
        return 1;
    }

    if (builtin.os.tag == .windows) _ = try std.os.windows.WSAStartup(2, 2);
    try ziget.ssl.init();

    var urlString : []const u8 = args[0];

    // default to http if no scheme provided
    if (std.mem.indexOf(u8, urlString, "://") == null) {
        urlString = try std.fmt.allocPrint(allocator, "http://{s}", .{urlString});
    }

    const url = try ziget.url.parseUrl(urlString);
    const options = ziget.request.DownloadOptions {
        .flags = 0,
        .allocator = allocator,
        .maxRedirects = maxRedirects,
        .forwardBufferSize = 8192,
        .maxHttpResponseHeaders = 8192,
        .onHttpRequest = sendingHttpRequest,
        .onHttpResponse = receivedHttpResponse,
    };

    const outFile = initOutFile: {
        const outFilename = initOutFilename: {
            if (downloadToStdout) {
                if (outFilenameOption) |_| {
                    printError("cannot specify both --stdout and --out", .{});
                    return 1;
                }
                break :initOutFile std.io.getStdOut();
            }
            if (outFilenameOption) |name|
                break :initOutFilename name;
            const name = std.fs.path.basename(url.getPathString());
            if (name.len == 0)
                break :initOutFilename "index.html";
            break :initOutFilename name;
        };
        break :initOutFile try std.fs.cwd().createFile(outFilename, .{});
    };
    defer {
        if (outFile.handle != std.io.getStdOut().handle)
            outFile.close();
    }

    var downloadState = ziget.request.DownloadState.init();
    ziget.request.download(url, outFile.writer(), options, &downloadState) catch |e| switch (e) {
        error.UnknownUrlScheme => {
            printError("unknown url scheme '{s}'", .{url.schemeString()});
            return 1;
        },
        else => return e,
    };
    return 0;
}

fn sendingHttpRequest(request: []const u8) void {
    std.debug.print("--------------------------------------------------------------------------------\n", .{});
    std.debug.print("Sending HTTP Request...\n", .{});
    std.debug.print("--------------------------------------------------------------------------------\n", .{});
    std.debug.print("{s}", .{request});
}
fn receivedHttpResponse(response: []const u8) void {
    std.debug.print("--------------------------------------------------------------------------------\n", .{});
    std.debug.print("Received Http Response:\n", .{});
    std.debug.print("--------------------------------------------------------------------------------\n", .{});
    std.debug.print("{s}", .{response});
}
