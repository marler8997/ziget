const std = @import("std");

const stdext = @import("stdext");
const readwrite = stdext.readwrite;

const ziget = @import("./ziget.zig");
const ssl = @import("ssl");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = &arena.allocator;

fn printError(comptime fmt: []const u8, args: var) void {
  std.debug.warn("Error: " ++ fmt ++ "\n", args);
}

fn usage() void {
    std.debug.warn(
      \\Usage: ziget [-options] <url>
      \\Options:
      \\  --out <file>         download to given file instead of url basename
      \\  --stdout             download to stdout
      \\  --max-redirs <num>   maximum number of redirects, default is 50
      , .{});
}

fn getArgOption(args: [][]const u8, i: *usize) []const u8 {
    i.* = i.* + 1;
    if (i.* >= args.len) {
        printError("option {} requires an argument", .{args[i.* - 1]});
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
                printError("unknown option '{}'", .{arg});
                return 1;
            }
        }
    }

    if (args.len != 1) {
        printError("expected 1 URL but got {} arguments", .{args.len});
        return 1;
    }

    if (std.builtin.os.tag == .windows) _ = try std.os.windows.WSAStartup(2, 2);
    try ssl.init();

    var urlString = args[0];

    // default to http if no scheme provided
    if (std.mem.indexOf(u8, urlString, "://") == null) {
        urlString = try std.fmt.allocPrint(allocator, "http://{}", .{urlString});
    }

    const url = try ziget.url.parseUrl(urlString);
    const buffer = try allocator.alloc(u8, 8192);
    defer allocator.free(buffer);
    const options = ziget.request.DownloadOptions {
        .flags =
              ziget.request.DownloadOptions.Flag.bufferIsMaxHttpRequest
            | ziget.request.DownloadOptions.Flag.bufferIsMaxHttpResponse,
        .allocator = allocator,
        .maxRedirects = maxRedirects,
        .buffer = buffer,
    };


    const outFile = initOutFile: {
        const outFilename = initOutFilename: {
            if (downloadToStdout) {
                if (outFilenameOption) |name| {
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
    var outFileRw = readwrite.FileReaderWriter.init(outFile);

    var downloadState = ziget.request.DownloadState.init();
    ziget.request.download(url, &outFileRw.rw.writer, options, &downloadState) catch |e| switch (e) {
        error.UnknownUrlScheme => {
            printError("unknown url scheme '{}'", .{url.schemeString()});
            return 1;
        },
        else => return e,
    };
    return 0;
}
