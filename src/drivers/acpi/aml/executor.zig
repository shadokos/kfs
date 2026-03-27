/// AML method execution engine -- public API.
///
/// This file re-exports the modular evaluator from eval/executor.zig.
/// All implementation lives in the eval/ directory.
const eval = @import("eval/executor.zig");

pub const Namespace = @import("../namespace/namespace.zig").Namespace;
pub const Node = @import("../namespace/node.zig").Node;
pub const Object = @import("objects.zig").Object;
pub const Error = eval.Error;
pub const EvalContext = eval.EvalContext;

pub const evaluate = eval.evaluate;
