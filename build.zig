const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

fn unwrapOptionalBool(optionalBool: ?bool) bool {
    if (optionalBool) |b| return b;
    return false;
}

pub fn build(b: *Builder) !void {
    const openssl = unwrapOptionalBool(b.option(bool, "openssl", "enable OpenSSL ssl backend"));
    //const wolfssl = unwrapOptionalBool(b.option(bool, "wolfssl", "enable WolfSSL ssl backend"));
    const iguana = unwrapOptionalBool(b.option(bool, "iguana", "enable IguanaTLS ssl backend"));
    if (openssl and iguana) {
        std.log.err("both '-Dopenssl' and '-Diguana' cannot be enabled at the same time", .{});
        std.os.exit(1);
    }

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("ziget", "ziget-cmdline.zig");
    exe.setTarget(target);
    exe.single_threaded = true;
    exe.setBuildMode(mode);
    if (openssl) {
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
    } else if (iguana) {
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
    } else {
        exe.addPackage(Pkg { .name = "ssl", .path = "nossl/ssl.zig" });
    }
    //if (wolfssl) {
    //    std.debug.print("Error: -Dwolfssl=true not implemented", .{});
    //    std.os.exit(1);
    //}
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);


    const test_exe = b.addExecutable("test", "test.zig");
    test_exe.setTarget(target);
    test_exe.setBuildMode(mode);

    const test_all_run_cmd = test_exe.run();
    const test_nossl_run_cmd = test_exe.run();
    test_nossl_run_cmd.addArg("nossl");
    const test_openssl_run_cmd = test_exe.run();
    test_openssl_run_cmd.addArg("openssl");
    const test_iguana_run_cmd = test_exe.run();
    test_iguana_run_cmd.addArg("iguana");

    test_all_run_cmd.step.dependOn(b.getInstallStep());
    test_nossl_run_cmd.step.dependOn(b.getInstallStep());
    test_openssl_run_cmd.step.dependOn(b.getInstallStep());
    test_iguana_run_cmd.step.dependOn(b.getInstallStep());

    const test_all_step = b.step("test-all", "Test ziget with all backends");
    test_all_step.dependOn(&test_all_run_cmd.step);
    const test_nossl_step = b.step("test-nossl", "Test ziget with the nossl backend");
    test_nossl_step.dependOn(&test_nossl_run_cmd.step);
    const test_openssl_step = b.step("test-openssl", "Test ziget with the openssl backend");
    test_openssl_step.dependOn(&test_openssl_run_cmd.step);
    const test_iguana_step = b.step("test-iguana", "Test ziget with the iguanaTLS backend");
    test_iguana_step.dependOn(&test_iguana_run_cmd.step);
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
