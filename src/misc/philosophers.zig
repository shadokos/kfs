const std = @import("std");
const tty = @import("../tty/tty.zig");
const get_time_since_boot = &@import("../timer.zig").get_time_since_boot;

const allocator = @import("../memory.zig").smallAlloc.allocator();

const task = @import("../task/task.zig");
const wait = @import("../task/wait.zig");
const Mutex = @import("../task/semaphore.zig").Mutex;

var start_time: u64 = 0;
var nb_philosophers: u8 = 5;
var time_to_die: usize = 410;
var time_to_eat: usize = 200;
var time_to_sleep: usize = 200;
var end_of_simulation: bool = false;
var eos_mutex = Mutex{};

pub const Philosopher = struct {
    const Self = @This();

    id: u8,
    left: *Mutex,
    right: *Mutex,
    forks_flag: struct { left: bool = false, right: bool = false } = .{},

    // num_of_eats: u32 = 0,

    last_meal: u64 = 0,
    last_sleep: u64 = 0,

    pub fn init(id: u8, left: *Mutex, right: *Mutex) Self {
        return Self{
            .id = id,
            .left = left,
            .right = right,
        };
    }

    // Compute a safe time to think: max 0, bounded so that at least time_to_eat remains before death.
    pub fn compute_think_time(self: *Self) usize {
        const now = get_time_since_boot() - start_time;
        const since_last_meal: usize = @intCast(now - self.last_meal);
        if (since_last_meal >= time_to_die) return 0;
        if (nb_philosophers == 1) return 0;
        if (time_to_die <= time_to_eat) return 0;

        const remaining_before_death = time_to_die - since_last_meal;
        if (remaining_before_death <= time_to_eat) return 0;

        return (remaining_before_death - time_to_eat) / 2;
    }

    // Sleep up to duration, but die if we reach death deadline during the sleep.
    pub fn sleep_until(self: *Self, duration: usize) void {
        const now = get_time_since_boot() - start_time;
        const since_last_meal: usize = @intCast(now - self.last_meal);

        if (since_last_meal >= time_to_die) {
            self.die();
            return;
        }

        const remaining_before_death = time_to_die - since_last_meal;

        if (duration >= remaining_before_death) {
            @import("../task/sleep.zig").sleep(remaining_before_death) catch {};
            self.die();
        } else {
            @import("../task/sleep.zig").sleep(duration) catch {};
        }
    }

    // Set end_of_simulation and exit, releasing any held forks.
    pub fn die(self: *Self) noreturn {
        eos_mutex.acquire();
        if (!end_of_simulation) {
            tty.printk("{} {} died\n", .{ get_time_since_boot() - start_time, self.id });
            end_of_simulation = true;
        }
        eos_mutex.release();
        // Will release forks (if any) and exit(0).
        self.check_eos();
        // check_eos exits; this point is unreachable, but keep noreturn contract.
        while (true) {}
    }

    pub fn take_forks(self: *Self) void {
        self.left.acquire();
        self.forks_flag.left = true;
        self.check_eos();
        // If we've already exceeded our deadline while waiting for the left fork, self-detect death.
        if (@as(usize, @intCast((get_time_since_boot() - start_time) - self.last_meal)) > time_to_die) {
            self.die();
        }
        tty.printk("{} {} has taken a fork\n", .{ get_time_since_boot() - start_time, self.id });

        self.right.acquire();
        self.forks_flag.right = true;
        self.check_eos();
        if (@as(usize, @intCast((get_time_since_boot() - start_time) - self.last_meal)) > time_to_die) {
            self.die();
        }
        tty.printk("{} {} has taken a fork\n", .{ get_time_since_boot() - start_time, self.id });
    }

    pub fn drop_forks(self: *Self) void {
        self.left.release();
        self.forks_flag.left = false;
        self.right.release();
        self.forks_flag.right = false;
    }

    pub fn eat(self: *Self) void {
        self.last_meal = get_time_since_boot() - start_time;
        self.check_eos();
        tty.printk("{} {} is eating\n", .{ self.last_meal, self.id });
        self.sleep_until(time_to_eat);
    }

    fn check_eos(self: *Self) void {
        eos_mutex.acquire();
        if (end_of_simulation) {
            eos_mutex.release();
            if (self.forks_flag.left) {
                self.left.release();
            }
            if (self.forks_flag.right) {
                self.right.release();
            }
            task.exit(0);
        }
        eos_mutex.release();
    }
};

fn philosopher_task(data: usize) u8 {
    const philosopher: *Philosopher = @ptrFromInt(data);

    if (philosopher.id % 2 == 1) {
        philosopher.sleep_until(time_to_eat / 2);
    }

    while (true) {
        // Early self-death check
        if (@as(usize, @intCast((get_time_since_boot() - start_time) - philosopher.last_meal)) > time_to_die) {
            philosopher.die();
        }

        // Think with bounded time to reduce contention and avoid late deaths
        tty.printk("{} {} is thinking\n", .{ get_time_since_boot() - start_time, philosopher.id });
        const think_time = philosopher.compute_think_time();
        if (think_time > 0) {
            philosopher.sleep_until(think_time);
        }

        philosopher.take_forks();
        philosopher.eat();
        philosopher.drop_forks();

        philosopher.check_eos();
        tty.printk("{} {} is sleeping\n", .{ get_time_since_boot() - start_time, philosopher.id });
        philosopher.sleep_until(time_to_sleep);
        philosopher.check_eos();
    }
    return 0;
}

pub fn main(nb: u8, ttd: usize, tte: usize, tts: usize) void {
    tty.printk("Starting philosophers\n", .{});

    nb_philosophers = nb;
    time_to_die = ttd;
    time_to_eat = tte;
    time_to_sleep = tts;
    end_of_simulation = false;

    start_time = get_time_since_boot();

    var mutexes: []Mutex = allocator.alloc(Mutex, nb_philosophers) catch @panic("Failed to allocate mutexes");
    var philosophers: []Philosopher = allocator.alloc(
        Philosopher,
        nb_philosophers,
    ) catch @panic("Failed to allocate philosophers");

    for (0..nb_philosophers) |i| {
        tty.printk("initializing philosopher {}\n", .{i});
        mutexes[i] = Mutex{};
        philosophers[i] = Philosopher.init(@intCast(i), &mutexes[i], &mutexes[(i + 1) % nb_philosophers]);
    }

    for (0..nb_philosophers) |i| {
        const d = @import("../task/task_set.zig").create_task() catch @panic("Failed to create new_task");
        _ = d.spawn(philosopher_task, @intFromPtr(&philosophers[i])) catch @panic("Failed to spawn philosopher task");
    }

    const current_pid = task.getpid();
    for (philosophers) |philo| {
        var stat: wait.Status = undefined;
        _ = wait.wait(
            current_pid,
            .CHILD,
            &stat,
            null,
            .{},
        ) catch std.log.warn("Failed to wait for philosopher {}", .{philo.id});
    }

    const status: bool = end_of_simulation;
    tty.printk("End of simulation {}\n", .{status});
}
