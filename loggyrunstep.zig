const builtin = @import("builtin");
const std = @import("std");
const RunStep = std.build.RunStep;
const print = std.debug.print;

// This saves the RunStep.make function pointer because it is private
var global_run_step_make: switch (builtin.zig_backend) {
    .stage1 => ?fn (step: *std.build.Step, prog_node: *std.Progress.Node) anyerror!void,
    else => ?*const fn (step: *std.build.Step, prog_node: *std.Progress.Node) anyerror!void,
} = null;

pub fn enable(run_step: *RunStep) void {
    // TODO: use an atomic operation
    if (global_run_step_make) |make| {
        std.debug.assert(run_step.step.makeFn == make);
    } else {
        global_run_step_make = run_step.step.makeFn;
    }
    run_step.step.makeFn = loggyRunStepMake;
}

fn printCmd(cwd: ?[]const u8, argv: []const []const u8) void {
    if (cwd) |yes_cwd| print("cd {s} && ", .{yes_cwd});
    for (argv) |arg| {
        print("{s} ", .{arg});
    }
    print("\n", .{});
}

fn loggyRunStepMake(step: *std.build.Step, prog_node: *std.Progress.Node) !void {
    const self = @fieldParentPtr(RunStep, "step", step);

    const cwd = if (self.cwd) |cwd| self.step.owner.pathFromRoot(cwd.path) else self.step.owner.build_root.path.?;

    var argv_list = std.ArrayList([]const u8).init(self.step.owner.allocator);
    for (self.argv.items) |arg| {
        switch (arg) {
            .bytes => |bytes| try argv_list.append(bytes),
            .lazy_path => |file| {
                if (file.prefix.len != 0) @panic("todo");
                try argv_list.append(file.lazy_path.getPath(self.step.owner));
            },
            .directory_source => @panic("todo"),
            .artifact => |artifact| {
                const executable_path = artifact.installed_path orelse artifact.getOutputSource().getPath(self.step.owner);
                try argv_list.append(executable_path);
            },
            .output => |output| {
                std.debug.panic("todo: convert output '{}' to argv string", .{output});
            },
        }
    }
    printCmd(cwd, argv_list.items);
    return global_run_step_make.?(step, prog_node);
}
