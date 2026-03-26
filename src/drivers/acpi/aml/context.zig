/// AML method execution context.
///
/// Manages the call stack for control method invocations (§5.5.2).
/// Each method frame holds the method's local variables (§5.5.2.3),
/// arguments (§5.5.2.1), and dynamically created namespace objects
/// that must be destroyed on method exit (§5.5.2.3).
const objects = @import("objects.zig");
const node_mod = @import("../namespace/node.zig");

const Object = objects.Object;
const Node = node_mod.Node;

/// Maximum method nesting depth.
/// The ACPI specification does not prescribe an explicit limit;
/// this is an implementation-defined safety bound.
pub const MAX_METHOD_DEPTH = 16;

/// Number of local variables per method frame: Local0..Local7 (§20.2.6.2 LocalObj).
/// Local0Op = 0x60 .. Local7Op = 0x67 (§20.2.6.2).
/// "Control methods can access up to eight local data objects" (§5.5.2.3).
pub const NUM_LOCALS = 8;

/// Number of arguments per method frame: Arg0..Arg6 (§20.2.6.1 ArgObj).
/// Arg0Op = 0x68 .. Arg6Op = 0x6E (§20.2.6.1).
/// "Up to seven arguments can be passed to a control method" (§5.5.2.1).
pub const NUM_ARGS = 7;

/// Maximum number of dynamic namespace nodes tracked per method frame.
/// Used to implement §5.5.2.3: "NameSpace objects created within the scope
/// of a method are dynamic. They exist only for the duration of the method
/// execution [...] and are destroyed on exit."
/// This is an implementation-defined limit.
pub const MAX_DYNAMIC_NODES = 8;

/// A single method invocation frame on the execution stack (§5.5.2).
///
/// Each invocation of a DefMethod (§20.2.5.2) creates one frame.
/// The MethodFlags byte (§20.2.5.2) determines the argument count,
/// serialization rule, and synchronization level of the method.
pub const MethodFrame = struct {
    /// Namespace node for the scope in which this method was defined
    /// (the NameString from DefMethod, §20.2.5.2).
    scope: *Node,
    /// AML bytecode slice for the method body (TermList from DefMethod).
    code: []const u8,
    /// Current program counter within `code`.
    pc: usize = 0,
    /// Local variables Local0..Local7 (§5.5.2.3, §20.2.6.2 LocalObj).
    /// Initialized to "uninitialized" per §5.5.2.3:
    /// "On initial control method execution, the local data objects are NULL."
    locals: [NUM_LOCALS]Object = [_]Object{.uninitialized} ** NUM_LOCALS,
    /// Arguments Arg0..Arg6 (§5.5.2.1, §20.2.6.1 ArgObj).
    /// The number of valid arguments is defined by MethodFlags bits [2:0]
    /// (§20.2.5.2); unused argument slots remain uninitialized.
    args: [NUM_ARGS]Object = [_]Object{.uninitialized} ** NUM_ARGS,
    /// Return value of this method invocation (§5.5.2.3).
    /// Set by DefReturn (ReturnOp, §20.2.5.3): "upon control method execution
    /// completion, one object can be returned."
    result: Object = .uninitialized,
    /// Dynamic namespace nodes created during this method's execution (§5.5.2.3).
    /// These nodes are destroyed when the method exits.
    dynamic_nodes: [MAX_DYNAMIC_NODES]?*Node = .{null} ** MAX_DYNAMIC_NODES,
    dynamic_count: u8 = 0,
    /// Set to true when a DefBreak (BreakOp 0xA5, §20.2.5.3) is pending.
    break_pending: bool = false,

    /// Track a dynamically created namespace node for cleanup on method exit.
    /// Implements the §5.5.2.3 requirement that method-scoped objects are
    /// destroyed when the method returns.
    pub fn track_dynamic_node(self: *MethodFrame, node: *Node) void {
        if (self.dynamic_count < self.dynamic_nodes.len) {
            self.dynamic_nodes[self.dynamic_count] = node;
            self.dynamic_count += 1;
        }
    }

    /// Remove all dynamically created nodes from the namespace (§5.5.2.3).
    /// Called on method exit to destroy method-scoped objects.
    pub fn cleanup_dynamic_nodes(self: *MethodFrame) void {
        for (self.dynamic_nodes[0..self.dynamic_count]) |maybe_node| {
            if (maybe_node) |node| {
                if (node.parent) |parent| {
                    parent.remove_child(node);
                }
            }
        }
        self.dynamic_count = 0;
    }
};

/// Method invocation stack (§5.5.2).
///
/// Maintains a fixed-depth stack of MethodFrame entries, one per nested
/// method call. Each push_frame corresponds to a MethodInvocation
/// (§20.2.5.4: MethodInvocation := NameString TermArgList) and each
/// pop_frame corresponds to either an explicit DefReturn (§20.2.5.3)
/// or an implicit return at the end of the TermList.
pub const Context = struct {
    frames: [MAX_METHOD_DEPTH]MethodFrame = undefined,
    depth: u8 = 0,

    /// Push a new method frame onto the stack.
    ///
    /// `scope` is the namespace node of the method being invoked.
    /// `code` is the AML bytecode for the method body (TermList).
    /// `args` are the evaluated TermArg values passed by the caller (§5.5.2.1).
    /// Arguments beyond NUM_ARGS (7) are silently ignored.
    pub fn push_frame(
        self: *Context,
        scope: *Node,
        code: []const u8,
        args: []const Object,
    ) !*MethodFrame {
        if (self.depth >= MAX_METHOD_DEPTH) return error.StackOverflow;
        const frame = &self.frames[self.depth];
        frame.* = .{
            .scope = scope,
            .code = code,
        };
        for (args, 0..) |arg, i| {
            if (i >= NUM_ARGS) break;
            frame.args[i] = arg;
        }
        self.depth += 1;
        return frame;
    }

    /// Pop the current method frame and return its result object.
    /// The result is set by DefReturn (§20.2.5.3) during method execution,
    /// or remains uninitialized if the method does not explicitly return.
    pub fn pop_frame(self: *Context) ?Object {
        if (self.depth == 0) return null;
        self.depth -= 1;
        return self.frames[self.depth].result;
    }

    /// Return a pointer to the currently executing method frame, or null
    /// if no method is executing.
    pub fn current(self: *Context) ?*MethodFrame {
        if (self.depth == 0) return null;
        return &self.frames[self.depth - 1];
    }

    /// Return the namespace scope node of the currently executing method.
    pub fn current_scope(self: *Context) ?*Node {
        const frame = self.current() orelse return null;
        return frame.scope;
    }
};
