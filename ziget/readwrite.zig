const std = @import("std");

pub const Reader = struct {
    readFn: fn(self: *Reader, data: []u8) anyerror!usize,
    pub fn read(self: *Reader, data: []u8) anyerror!usize {
        return self.readFn(self, data);
    }
};
pub const Writer = struct {
    writeFn: fn(self: *Writer, data: []const u8) anyerror!void,
    pub fn write(self: *Writer, data: []const u8) !void {
        return self.writeFn(self, data);
    }
};
pub const ReaderWriter = struct {
    reader: Reader,
    writer: Writer,
};
pub const FileReaderWriter = struct {
    rw: ReaderWriter,
    file: std.fs.File,
    pub fn init(file: std.fs.File) FileReaderWriter {
        return .{
            .rw = .{
                .reader = .{.readFn = read},
                .writer = .{.writeFn = write},
            },
            .file = file
        };
    }
    pub fn read(reader: *Reader, data: []u8) anyerror!usize {
        const self = @fieldParentPtr(FileReaderWriter, "rw",
            @fieldParentPtr(ReaderWriter, "reader", reader));
        return try self.file.read(data);
    }
    pub fn write(writer: *Writer, data: []const u8) anyerror!void {
        const self = @fieldParentPtr(FileReaderWriter, "rw",
            @fieldParentPtr(ReaderWriter, "writer", writer));
        try self.file.writeAll(data);
    }
};

fn writeStdout(writer: *Writer, data: []const u8) anyerror!void {
    try std.io.getStdOut().writeAll(data);
}
pub var stdoutWriter = Writer { .writeFn = writeStdout };
