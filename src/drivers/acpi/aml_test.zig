/// AML interpreter test runner.
///
/// Tests are ASL files compiled to AML and loaded into QEMU via `-acpitable`.
/// The kernel discovers them as SSDTs, loads them into the live namespace,
/// then `amltest` evaluates each MAIN method.
///
/// Run via the `amltest` shell builtin, or individually:
///   acpi_eval \_SB._KFS.TART.MAIN
const std = @import("std");
const executor = @import("aml/executor.zig");
const Namespace = @import("namespace/namespace.zig").Namespace;

const TestCase = struct {
    name: []const u8,
    main_path: []const u8,
};

const test_suite = [_]TestCase{
    .{ .name = "arith", .main_path = "\\_SB._KFS.TART.MAIN" },
    .{ .name = "logic", .main_path = "\\_SB._KFS.TLOG.MAIN" },
    .{ .name = "flow", .main_path = "\\_SB._KFS.TFLW.MAIN" },
    .{ .name = "store", .main_path = "\\_SB._KFS.TSTO.MAIN" },
    .{ .name = "method", .main_path = "\\_SB._KFS.TMTH.MAIN" },
    .{ .name = "names", .main_path = "\\_SB._KFS.TNAM.MAIN" },
    .{ .name = "data", .main_path = "\\_SB._KFS.TDAT.MAIN" },
    .{ .name = "hw", .main_path = "\\_SB._KFS.THW0.MAIN" },
    .{ .name = "conv", .main_path = "\\_SB._KFS.TCNV.MAIN" },
    .{ .name = "compare", .main_path = "\\_SB._KFS.TSCM.MAIN" },
    .{ .name = "ns", .main_path = "\\_SB._KFS.TNS0.MAIN" },
    .{ .name = "ref2", .main_path = "\\_SB._KFS.TRF2.MAIN" },
    .{ .name = "field2", .main_path = "\\_SB._KFS.TFD2.MAIN" },
    .{ .name = "notify", .main_path = "\\_SB._KFS.TNFY.MAIN" },
};

/// Run tests from the live ACPI namespace (loaded via QEMU -acpitable).
/// Returns number of failures (1 if no tests found).
pub fn run_ns_tests(ns: *Namespace, writer: std.io.AnyWriter) usize {
    var passed: usize = 0;
    var failed: usize = 0;
    var found: usize = 0;

    var global_pcnt: u64 = 0;
    var global_tcnt: u64 = 0;

    writer.print("AML interpreter tests:\n", .{}) catch {};

    for (test_suite) |t| {
        const main_node = ns.resolve_path(t.main_path) orelse continue;
        found += 1;

        const result = executor.evaluate(ns, main_node, &.{}) catch |err| {
            writer.print("  {s}: FAIL (eval: {s})\n", .{ t.name, @errorName(err) }) catch {};
            failed += 1;
            continue;
        };

        // Extract the base path (e.g. \_SB._KFS.TART) by stripping ".MAIN"
        const base_path = t.main_path[0 .. t.main_path.len - 5];
        var pcnt: u64 = 0;
        var tcnt: u64 = 0;

        // Fetch PCNT dynamically
        var pcnt_buf: [64]u8 = undefined;
        if (std.fmt.bufPrint(&pcnt_buf, "{s}.PCNT", .{base_path})) |pcnt_path| {
            if (ns.resolve_path(pcnt_path)) |pcnt_node| {
                if (executor.evaluate(ns, pcnt_node, &.{})) |p_res| {
                    pcnt = p_res.to_integer() orelse 0;
                } else |_| {}
            }
        } else |_| {}

        // Fetch TCNT dynamically
        var tcnt_buf: [64]u8 = undefined;
        if (std.fmt.bufPrint(&tcnt_buf, "{s}.TCNT", .{base_path})) |tcnt_path| {
            if (ns.resolve_path(tcnt_path)) |tcnt_node| {
                if (executor.evaluate(ns, tcnt_node, &.{})) |t_res| {
                    tcnt = t_res.to_integer() orelse 0;
                } else |_| {}
            }
        } else |_| {}

        global_pcnt += pcnt;
        global_tcnt += tcnt;

        report(writer, t.name, result, pcnt, tcnt, &passed, &failed);
    }

    if (found == 0) {
        writer.print("  ERROR: no test SSDTs found in namespace\n", .{}) catch {};
        writer.print("  (are -acpitable flags passed to QEMU?)\n", .{}) catch {};
        return 1;
    }

    writer.print("\nResults: {d} modules passed, {d} modules failed\n", .{ passed, failed }) catch {};
    writer.print("Total assertions: {d}/{d} passed\n", .{ global_pcnt, global_tcnt }) catch {};

    return failed;
}

fn report(
    writer: std.io.AnyWriter,
    name: []const u8,
    result: @import("aml/objects.zig").Object,
    pcnt: u64,
    tcnt: u64,
    passed: *usize,
    failed: *usize,
) void {
    const val = result.to_integer() orelse {
        writer.print(
            "  {s}: FAIL (non-integer: {s}) [{d}/{d}]\n",
            .{ name, @tagName(result), pcnt, tcnt },
        ) catch {};
        failed.* += 1;
        return;
    };

    if (val == 0) {
        writer.print(
            "  {s}: OK ({d}/{d})\n",
            .{ name, pcnt, tcnt },
        ) catch {};
        passed.* += 1;
    } else {
        writer.print(
            "  {s}: FAIL at 0x{X} ({d}/{d} passed)\n",
            .{ name, val, pcnt, tcnt },
        ) catch {};
        failed.* += 1;
    }
}
