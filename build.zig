const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

fn unwrapOptionalBool(optionalBool: ?bool) bool {
    if (optionalBool) |b| return b;
    return false;
}

const SslBackend = enum {
    nossl,
    openssl,
    wolfssl,
    iguana,
    schannel,
};
const ssl_backends = @typeInfo(SslBackend).Enum.fields;

pub fn getSslBackend(b: *Builder) SslBackend {

    var backend: SslBackend = SslBackend.nossl; // default to nossl

    var backend_infos : [ssl_backends.len]struct {
        enabled: bool,
        name: []const u8,
    } = undefined;
    var backend_enabled_count: u32 = 0;
    inline for (ssl_backends) |field, i| {
        const enabled = unwrapOptionalBool(b.option(bool, field.name, "enable ssl backend: " ++ field.name));
        if (enabled) {
            backend = @field(SslBackend, field.name);
            backend_enabled_count += 1;
        }
        backend_infos[i] = .{
            .enabled = enabled,
            .name = field.name,
        };
    }
    if (backend_enabled_count > 1) {
        std.log.err("only one ssl backend may be enabled, can't provide these options at the same time:", .{});
        for (backend_infos) |info| {
            if (info.enabled) {
                std.log.err("    -D{s}", .{info.name});
            }
        }
        std.os.exit(1);
    }
    return backend;
}

pub fn build(b: *Builder) !void {
    const ssl_backend = getSslBackend(b);

    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("ziget", "ziget-cmdline.zig");
    exe.setTarget(target);
    exe.single_threaded = true;
    exe.setBuildMode(mode);
    switch (ssl_backend) {
        .nossl => {
            exe.addPackage(Pkg { .name = "ssl", .path = "nossl/ssl.zig" });
        },
        .openssl => {
            exe.addPackage(Pkg { .name = "ssl", .path = "openssl/ssl.zig" });
            exe.linkSystemLibrary("c");
            if (std.builtin.os.tag == .windows) {
                exe.linkSystemLibrary("libcrypto");
                exe.linkSystemLibrary("libssl");
                try setupOpensslWindows(b, exe);
            } else {
                exe.linkSystemLibrary("crypto");
                exe.linkSystemLibrary("ssl");
            }
        },
        .wolfssl => {
            std.log.err("-Dwolfssl is not implemented", .{});
            std.os.exit(1);
        },
        .iguana => {
            const iguana_index_file = try getPackageIndex(b.allocator,
                "https://github.com/alexnask/iguanaTLS",
                "src" ++ std.fs.path.sep_str ++ "main.zig");
            exe.addPackage(Pkg {
                .name = "ssl",
                .path = "iguana/ssl.zig",
                .dependencies = &[_]Pkg {
                    .{ .name = "iguana", .path = iguana_index_file },
                },
            });
        },
        .schannel => {
            const zigwin32_index_file = try getPackageIndex(b.allocator,
                "https://github.com/marlersoft/zigwin32",
                "src" ++ std.fs.path.sep_str ++ "win32.zig");
            exe.addPackage(Pkg {
                .name = "ssl",
                .path = "schannel/ssl.zig",
                .dependencies = &[_]Pkg {
                    .{ .name = "win32", .path = zigwin32_index_file },
                },
            });
            // NOTE: for now I'm using msspi from https://github.com/deemru/msspi
            //       I'll probably port this to Zig at some point
            //       Once I do remove this build config
            // NOTE: I tested using this commit: 7338760a4a2c6fb80c47b24a2abba32d5fc40635 tagged at version 0.1.42
            const msspi_repo = try getGitRepo(b.allocator, "https://github.com/deemru/msspi");
            const msspi_src_dir = try std.fs.path.join(b.allocator, &[_][]const u8 { msspi_repo, "src" });
            const msspi_main_cpp = try std.fs.path.join(b.allocator, &[_][]const u8 { msspi_src_dir, "msspi.cpp" });
            const msspi_third_party_include = try std.fs.path.join(b.allocator, &[_][]const u8 { msspi_repo, "third_party", "cprocsp", "include" });
            std.log.debug("main_cpp is '{s}'\n", .{msspi_main_cpp});
            exe.addCSourceFile(msspi_main_cpp, &[_][]const u8 { });
            exe.addIncludeDir(msspi_src_dir);
            exe.addIncludeDir(msspi_third_party_include);
            exe.linkLibC();
            exe.linkSystemLibrary("ws2_32");
            exe.linkSystemLibrary("crypt32");
            exe.linkSystemLibrary("advapi32");
        },
    }
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    addTests(b, target, mode);
}

fn addTests(b: *Builder, target: std.zig.CrossTarget, mode: std.builtin.Mode) void {
    const test_exe = b.addExecutable("test", "test.zig");
    test_exe.setTarget(target);
    test_exe.setBuildMode(mode);

    const test_step = b.step("test", "Run all the 'Enabled' tests");

    var backend_tests : [ssl_backends.len]struct {
        run_cmd: *std.build.RunStep,
    } = undefined;
    inline for (ssl_backends) |field, i| {
        const enum_value = @field(SslBackend, field.name);
        const enabled_by_default =
            if (enum_value == .wolfssl) false
            else if (enum_value == .schannel and std.builtin.os.tag != .windows) false
            else true;

        backend_tests[i].run_cmd = test_exe.run();
        backend_tests[i].run_cmd.addArg(field.name);
        backend_tests[i].run_cmd.step.dependOn(b.getInstallStep());
        const enabled_prefix = if (enabled_by_default) "Enabled " else "Disabled";
        const test_backend_step = b.step("test-" ++ field.name,
            enabled_prefix ++ ": test ziget with the '" ++ field.name ++ "' ssl backend");
        test_backend_step.dependOn(&backend_tests[i].run_cmd.step);

        if (enabled_by_default) {
            test_step.dependOn(&backend_tests[i].run_cmd.step);
        }
    }
}


fn setupOpensslWindows(b: *Builder, exe: *std.build.LibExeObjStep) !void {
    const openssl_path = b.option([]const u8, "openssl-path", "path to openssl (for Windows)") orelse {
        std.debug.print("Error: -Dopenssl on windows requires -Dopenssl-path=DIR to be specified\n", .{});
        std.os.exit(1);
    };
    // NOTE: right now these files are hardcoded to the files expected when installing SSL via
    //       this web page: https://slproweb.com/products/Win32OpenSSL.html and installed using
    //       this exe installer: https://slproweb.com/download/Win64OpenSSL-1_1_1g.exe
    exe.addIncludeDir(try std.fs.path.join(b.allocator, &[_][]const u8 {openssl_path, "include"}));
    exe.addLibPath(try std.fs.path.join(b.allocator, &[_][]const u8 {openssl_path, "lib"}));
    // install dlls to the same directory as executable
    for ([_][]const u8 {"libcrypto-1_1-x64.dll", "libssl-1_1-x64.dll"}) |dll| {
        exe.step.dependOn(
            &b.addInstallFileWithDir(
                try std.fs.path.join(b.allocator, &[_][]const u8 {openssl_path, dll}),
                .Bin,
                dll,
            ).step
        );
    }
}

fn getGitRepo(allocator: *std.mem.Allocator, url: []const u8) ![]const u8 {
    const repo_path = init: {
        const cwd = try std.process.getCwdAlloc(allocator);
        defer allocator.free(cwd);
        break :init try std.fs.path.join(allocator,
            &[_][]const u8{ std.fs.path.dirname(cwd).?, std.fs.path.basename(url) }
        );
    };
    errdefer allocator.free(repo_path);

    std.fs.accessAbsolute(repo_path, std.fs.File.OpenFlags { .read = true }) catch |err| {
        std.debug.print("Error: repository '{s}' does not exist\n", .{repo_path});
        std.debug.print("       Run the following to clone it:\n", .{});
        std.debug.print("       git clone {s} {s}\n", .{url, repo_path});
        std.os.exit(1);
    };
    return repo_path;
}
fn getPackageIndex(allocator: *std.mem.Allocator, url: []const u8, index_sub_path: []const u8) ![]const u8 {
    const repo_path = try getGitRepo(allocator, url);
    defer allocator.free(repo_path);
    return try std.fs.path.join(allocator, &[_][]const u8 { repo_path, index_sub_path });
}
