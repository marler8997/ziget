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
    exe.setBuildMode(mode);
    exe.addPackage(Pkg { .name = "stdext", .path = "src-stdext/stdext.zig" });
    if (openssl) {
        exe.addPackage(Pkg { .name = "ssl", .path = "openssl/ssl.zig" });
        exe.linkSystemLibrary("c");
        exe.linkSystemLibrary("ssl");
        exe.linkSystemLibrary("crypto");
    } else {
        exe.addPackage(Pkg { .name = "ssl", .path = "nossl/ssl.zig" });
    }
    //if (wolfssl) {
    //    std.debug.warn("Error: -Dwolfssl=true not implemented", .{});
    //    std.os.exit(1);
    //}
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
