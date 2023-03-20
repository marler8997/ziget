const std = @import("std");
const builtin = @import("builtin");
const Builder = std.build.Builder;
const Module = std.build.Module;
const GitRepoStep = @import("GitRepoStep.zig");
const loggyrunstep = @import("loggyrunstep.zig");

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_ci = if (b.option(bool, "is_ci", "is the CI")) |o| o else false;
    const build_all_step = b.step("all", "Build ziget with all the 'enabled' backends");
    const nossl_exe = addExe(b, target, optimize, null, build_all_step, is_ci);
    var ssl_exes: [ssl_backends.len]*std.build.CompileStep = undefined;
    inline for (ssl_backends, 0..) |field, i| {
        const enum_value = @field(SslBackend, field.name);
        ssl_exes[i] = addExe(b, target, optimize, enum_value, build_all_step, is_ci);
    }

    const test_all_step = b.step("test", "Run all the 'Enabled' tests");
    addTest(b, test_all_step, "nossl", nossl_exe, null, is_ci);
    inline for (ssl_backends, 0..) |field, i| {
        const enum_value = @field(SslBackend, field.name);
        addTest(b, test_all_step, field.name, ssl_exes[i], enum_value, is_ci);
    }

    // by default, install the std ssl backend
    const default_exe = ssl_exes[@enumToInt(SslBackend.std)];
    b.getInstallStep().dependOn(&default_exe.install_step.?.step);
    const run_cmd = default_exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run ziget with the std ssl backend");
    run_step.dependOn(&run_cmd.step);
}

fn getEnabledByDefault(optional_ssl_backend: ?SslBackend, is_ci: bool) bool {
    return if (optional_ssl_backend) |backend| switch (backend) {
        .std => true,
        .schannel => false, // schannel not supported yet
        .opensslstatic => (
               builtin.os.tag == .linux
            // or builtin.os.tag == .macos (not working yet, I think config is not working)
        ),
        .openssl => (
            (builtin.os.tag == .linux and !is_ci) // zig is having trouble with the openssh headers on the CI
            // or builtin.os.tag == .macos (not working yet, not sure why)
        ),
    } else true;
}

fn addExe(
    b: *Builder,
    target: std.zig.CrossTarget,
    optimize: std.builtin.Mode,
    comptime optional_ssl_backend: ?SslBackend,
    build_all_step: *std.build.Step,
    is_ci: bool,
) *std.build.CompileStep {
    const info: struct { name: []const u8, exe_suffix: []const u8 } = comptime if (optional_ssl_backend) |backend| .{
        .name = @tagName(backend),
        .exe_suffix = if (backend == .std) "" else ("-" ++ @tagName(backend)),
    } else .{
        .name = "nossl",
        .exe_suffix = "-nossl",
    };

    const exe = b.addExecutable(.{
        .name = "ziget" ++ info.exe_suffix,
        .root_source_file = .{ .path = "ziget-cmdline.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.single_threaded = true;
    addZigetModule(exe, optional_ssl_backend, ".");
    const install = b.addInstallArtifact(exe);
    const enabled_by_default = getEnabledByDefault(optional_ssl_backend, is_ci);
    if (enabled_by_default) {
        build_all_step.dependOn(&install.step);
    }
    const abled_suffix: []const u8 = if (enabled_by_default) "" else " (DISABLED BY DEFAULT)";
    b.step(info.name, b.fmt("Build ziget with the {s} backend{s}", .{
        info.name,
        abled_suffix,
    })).dependOn(
        &install.step
    );
    return exe;
}

fn addTest(
    b: *Builder,
    test_all_step: *std.build.Step,
    comptime backend_name: []const u8,
    exe: *std.build.CompileStep,
    optional_ssl_backend: ?SslBackend,
    is_ci: bool,
) void {
    const enabled_by_default = getEnabledByDefault(optional_ssl_backend, is_ci);
    const abled_suffix: []const u8 = if (enabled_by_default) "" else " (DISABLED BY DEFAULT)";
    const test_backend_step = b.step(
        "test-" ++ backend_name,
        b.fmt("Test the {s} backend{s}", .{backend_name, abled_suffix})
    );
    {
        const run = exe.run();
        run.addArg("http://google.com");
        loggyrunstep.enable(run);
        test_backend_step.dependOn(&run.step);
    }
    if (optional_ssl_backend) |_| {
        {
            const run = exe.run();
            run.addArg("http://ziglang.org"); // NOTE: ziglang.org will redirect to HTTPS
            loggyrunstep.enable(run);
            test_backend_step.dependOn(&run.step);
        }
        {
            const run = exe.run();
            run.addArg("https://ziglang.org");
            loggyrunstep.enable(run);
            test_backend_step.dependOn(&run.step);
        }
    } else {
        const run = exe.run();
        run.addArg("google.com");
        loggyrunstep.enable(run);
        test_backend_step.dependOn(&run.step);
    }
    if (getEnabledByDefault(optional_ssl_backend, is_ci)) {
        test_all_step.dependOn(test_backend_step);
    }
}

pub const SslBackend = enum {
    std,
    openssl,
    opensslstatic,
    schannel,
};
pub const ssl_backends = @typeInfo(SslBackend).Enum.fields;

///! Adds the ziget package to the given compile step.
///! This function will add the necessary include directories, libraries, etc to be able to
///! include ziget and it's SSL backend dependencies into the given compile.
pub fn addZigetModule(
    compile: *std.build.CompileStep,
    optional_ssl_backend: ?SslBackend,
    ziget_repo: []const u8,
) void {
    const b = compile.step.owner;
    const ziget_index = std.fs.path.join(b.allocator, &[_][]const u8 { ziget_repo, "ziget.zig" }) catch unreachable;
    const ssl_module = if (optional_ssl_backend) |backend| addSslBackend(compile, backend, ziget_repo)
        else b.createModule(.{ .source_file = .{ .path = "nossl/ssl.zig" } });
    compile.addAnonymousModule("ziget", .{
        .source_file = .{ .path = ziget_index },
        .dependencies = &[_]std.Build.ModuleDependency {
            .{ .name = "ssl", .module = ssl_module },
        },
    });
}

fn addSslBackend(compile: *std.build.CompileStep, backend: SslBackend, ziget_repo: []const u8) *Module {
    const b = compile.step.owner;
    switch (backend) {
        .std => return b.createModule(.{
            .source_file = .{ .path = std.fs.path.join(b.allocator, &[_][]const u8 { ziget_repo, "stdssl.zig" }) catch unreachable },
        }),
        .openssl => {
            compile.linkSystemLibrary("c");
            if (builtin.os.tag == .windows) {
                compile.linkSystemLibrary("libcrypto");
                compile.linkSystemLibrary("libssl");
                setupOpensslWindows(compile);
            } else {
                compile.linkSystemLibrary("crypto");
                compile.linkSystemLibrary("ssl");
            }
            return b.createModule(.{
                .source_file = .{ .path = std.fs.path.join(b.allocator, &[_][]const u8 { ziget_repo, "openssl", "ssl.zig" }) catch unreachable}
            });
        },
        .opensslstatic => {
            const openssl_repo = GitRepoStep.create(b, .{
                .url = "https://github.com/openssl/openssl",
                .branch = "OpenSSL_1_1_1j",
                .sha = "52c587d60be67c337364b830dd3fdc15404a2f04",
            });

            // TODO: should we implement something to cache the configuration?
            //       can the configure output be in a different directory?
            {
                const configure_openssl = std.build.RunStep.create(b, "configure openssl");
                configure_openssl.step.dependOn(&openssl_repo.step);
                configure_openssl.cwd = openssl_repo.getPath(&configure_openssl.step);
                configure_openssl.addArgs(&[_][]const u8 {
                    "./config",
                    // just a temporary path for now
                    //"--openssl",
                    //"/tmp/ziget-openssl-static-dir1",
                    "-static",
                    // just disable everything for now
                    "no-threads",
                    "no-shared",
                    "no-asm",
                    "no-sse2",
                    "no-aria",
                    "no-bf",
                    "no-camellia",
                    "no-cast",
                    "no-des",
                    "no-dh",
                    "no-dsa",
                    "no-ec",
                    "no-idea",
                    "no-md2",
                    "no-mdc2",
                    "no-rc2",
                    "no-rc4",
                    "no-rc5",
                    "no-seed",
                    "no-sm2",
                    "no-sm3",
                    "no-sm4",
                });
                configure_openssl.addCheck(.{
                    .expect_stdout_match = "OpenSSL has been successfully configured",
                });
                const make_openssl = std.build.RunStep.create(b, "configure openssl");
                make_openssl.cwd = configure_openssl.cwd;
                make_openssl.addArgs(&[_][]const u8 {
                    "make",
                    "include/openssl/opensslconf.h",
                    "include/crypto/bn_conf.h",
                    "include/crypto/dso_conf.h",
                });
                make_openssl.step.dependOn(&configure_openssl.step);
                compile.step.dependOn(&make_openssl.step);
            }

            const openssl_repo_path_for_step = openssl_repo.getPath(&compile.step);
            compile.addIncludePath(openssl_repo_path_for_step);
            compile.addIncludePath(std.fs.path.join(b.allocator, &[_][]const u8 {
                openssl_repo_path_for_step, "include" }) catch unreachable);
            compile.addIncludePath(std.fs.path.join(b.allocator, &[_][]const u8 {
                openssl_repo_path_for_step, "crypto", "modes" }) catch unreachable);
            const cflags = &[_][]const u8 {
                "-Wall",
                // TODO: is this the right way to do this? is it a config option?
                "-DOPENSSL_NO_ENGINE",
                // TODO: --openssldir doesn't seem to be setting this?
                "-DOPENSSLDIR=\"/tmp/ziget-openssl-static-dir2\"",
            };
            {
                const sources = @embedFile("openssl/sources");
                var source_lines = std.mem.split(u8, sources, "\n");
                while (source_lines.next()) |src| {
                    if (src.len == 0 or src[0] == '#') continue;
                    compile.addCSourceFile(std.fs.path.join(b.allocator, &[_][]const u8 {
                        openssl_repo_path_for_step, src }) catch unreachable, cflags);
                }
            }
            compile.linkLibC();
            return b.createModule(.{
                .source_file = .{ .path = std.fs.path.join(b.allocator, &[_][]const u8 { ziget_repo, "openssl", "ssl.zig" }) catch unreachable},
            });
        },
        .schannel => {
            {
                // NOTE: for now I'm using msspi from https://github.com/deemru/msspi
                //       I'll probably port this to Zig at some point
                //       Once I do remove this build config
                // NOTE: I tested using this commit: 7338760a4a2c6fb80c47b24a2abba32d5fc40635 tagged at version 0.1.42
                const msspi_repo = GitRepoStep.create(b, .{
                    .url = "https://github.com/deemru/msspi",
                    .branch = "0.1.42",
                    .sha = "7338760a4a2c6fb80c47b24a2abba32d5fc40635"
                });
                compile.step.dependOn(&msspi_repo.step);
                const msspi_repo_path = msspi_repo.getPath(&compile.step);

                const msspi_src_dir = std.fs.path.join(b.allocator, &[_][]const u8 { msspi_repo_path, "src" }) catch unreachable;
                const msspi_main_cpp = std.fs.path.join(b.allocator, &[_][]const u8 { msspi_src_dir, "msspi.cpp" }) catch unreachable;
                const msspi_third_party_include = std.fs.path.join(b.allocator, &[_][]const u8 { msspi_repo_path, "third_party", "cprocsp", "include" }) catch unreachable;
                compile.addCSourceFile(msspi_main_cpp, &[_][]const u8 { });
                compile.addIncludePath(msspi_src_dir);
                compile.addIncludePath(msspi_third_party_include);
                compile.linkLibC();
                compile.linkSystemLibrary("ws2_32");
                compile.linkSystemLibrary("crypt32");
                compile.linkSystemLibrary("advapi32");
            }
            // TODO: this will be needed if/when msspi is ported to Zig
            //const zigwin32_index_file = try getGitRepoFile(b.allocator,
            //    "https://github.com/marlersoft/zigwin32",
            //    "src" ++ std.fs.path.sep_str ++ "win32.zig");
            return b.createModule(.{
                .source_file = .{ .path = std.fs.path.join(b.allocator, &[_][]const u8 { ziget_repo, "schannel", "ssl.zig" }) catch unreachable },
                //.dependencies = &[_]Module {
                //    .{ .name = "win32", .source = .{ .path = zigwin32_index_file } },
                //},
            });
        }
    }
}

const OpensslPathOption = struct {
    // NOTE: I can't use ??[]const u8 because it exposes a bug in the compiler
    is_cached: bool = false,
    cached: ?[]const u8 = undefined,
    fn get(self: *OpensslPathOption, b: *std.build.Builder) ?[]const u8 {
        if (!self.is_cached) {
            self.cached = b.option(
                []const u8,
                "openssl-path",
                "path to openssl (for Windows)",
            );
            self.is_cached = true;
        }
        std.debug.assert(self.is_cached);
        return self.cached;
    }
};
var global_openssl_path_option = OpensslPathOption { };

pub fn setupOpensslWindows(compile: *std.build.CompileStep) void {
    const b = compile.step.owner;

    const openssl_path = global_openssl_path_option.get(b) orelse {
        compile.step.dependOn(&FailStep.create(b, "missing openssl-path",
            "-Dopenssl on windows requires -Dopenssl-path=DIR to be specified").step);
        return;
    };
    // NOTE: right now these files are hardcoded to the files expected when installing SSL via
    //       this web page: https://slproweb.com/products/Win32OpenSSL.html and installed using
    //       this exe installer: https://slproweb.com/download/Win64OpenSSL-1_1_1g.exe
    compile.addIncludePath(std.fs.path.join(b.allocator, &[_][]const u8 {openssl_path, "include"}) catch unreachable);
    compile.addLibraryPath(std.fs.path.join(b.allocator, &[_][]const u8 {openssl_path, "lib"}) catch unreachable);
    // install dlls to the same directory as executable
    for ([_][]const u8 {"libcrypto-1_1-x64.dll", "libssl-1_1-x64.dll"}) |dll| {
        compile.step.dependOn(
            &b.addInstallFileWithDir(
                .{ .path = std.fs.path.join(b.allocator, &[_][]const u8 {openssl_path, dll}) catch unreachable },
                .bin,
                dll,
            ).step
        );
    }
}

const FailStep = struct {
    step: std.build.Step,
    fail_msg: []const u8,
    pub fn create(b: *Builder, name: []const u8, fail_msg: []const u8) *FailStep {
        var result = b.allocator.create(FailStep) catch unreachable;
        result.* = .{
            .step = std.build.Step.init(.{
                .id = .custom,
                .name = name,
                .owner = b,
                .makeFn = make,
            }),
            .fail_msg = fail_msg,
        };
        return result;
    }
    fn make(step: *std.build.Step, prog_node: *std.Progress.Node) !void {
        _ = prog_node;
        const self = @fieldParentPtr(FailStep, "step", step);
        std.log.err("{s}", .{self.fail_msg});
        std.os.exit(0xff);
    }
};
