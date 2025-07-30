// src/task/sleep_timer.zig
const TaskDescriptor = @import("task.zig").TaskDescriptor;
const tsc = @import("../cpu/tsc.zig");

pub const SleepNode = struct {
    // task: *TaskDescriptor,
    wake_time: u64, // Temps absolu de réveil en nanosecondes
    next: ?*SleepNode = null,
    prev: ?*SleepNode = null,
};

pub const SleepQueue = struct {
    head: ?*SleepNode = null,

    // Insère un nœud dans la liste triée par wake_time
    pub fn insert(self: *SleepQueue, node: *SleepNode) void {
        var current = self.head;
        var prev: ?*SleepNode = null;

        // Trouve la position d'insertion (liste triée)
        while (current) |curr| {
            if (node.wake_time < curr.wake_time) break;
            prev = curr;
            current = curr.next;
        }

        // Insère le nœud
        node.next = current;
        node.prev = prev;

        if (current) |curr| curr.prev = node;
        if (prev) |p| {
            p.next = node;
        } else {
            self.head = node;
        }
    }

    // Récupère le prochain temps de réveil
    pub fn get_next_wake_time(self: *const SleepQueue) ?u64 {
        if (self.head) |head| {
            return head.wake_time;
        }
        return null;
    }

    // Retire et retourne toutes les tâches dont le temps est écoulé
    pub fn pop_ready(self: *SleepQueue, current_time: u64) ?*SleepNode {
        if (self.head) |head| {
            if (head.wake_time <= current_time) {
                self.head = head.next;
                if (self.head) |new_head| new_head.prev = null;
                head.next = null;
                head.prev = null;
                return head;
            }
        }
        return null;
    }
};
