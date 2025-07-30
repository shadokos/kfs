const ft = @import("ft");
const tty = @import("../tty/tty.zig");
const get_time_since_boot = &@import("../drivers/apic/timer.zig").get_time_since_boot;

const allocator = @import("../memory.zig").smallAlloc.allocator();

const task = @import("../task/task.zig");
const wait = @import("../task/wait.zig");
const scheduler = @import("../task/scheduler.zig");
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

    pub fn take_forks(self: *Self) void {
        self.left.acquire();
        self.forks_flag.left = true;
        self.check_eos();
        tty.printk("{} {} has taken a fork\n", .{ get_time_since_boot() - start_time, self.id });
        self.right.acquire();
        self.forks_flag.right = true;
        self.check_eos();
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
        @import("../task/sleep.zig").sleep(time_to_eat) catch {};
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
        @import("../task/sleep.zig").sleep(time_to_eat / 2) catch {};
    }

    while (true) {
        philosopher.take_forks();
        philosopher.eat();
        philosopher.drop_forks();
        philosopher.check_eos();
        tty.printk("{} {} is sleeping\n", .{ get_time_since_boot() - start_time, philosopher.id });
        @import("../task/sleep.zig").sleep(time_to_sleep) catch {};
        philosopher.check_eos();
        tty.printk("{} {} is thinking\n", .{ get_time_since_boot() - start_time, philosopher.id });
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
    tty.printk("start_time {} ms\n", .{start_time});

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

    const status: bool = b: while (true) {
        for (philosophers) |philo| {
            eos_mutex.acquire();
            const time_since_boot = get_time_since_boot();
            const start = start_time;
            const t_td = time_to_die;
            // tty.printk("{}: {} - {} - {} > {}\n", .{
            //     philo.id,
            //     time_since_boot,
            //     start,
            //     philo.last_meal,
            //     t_td
            // });
            if (time_since_boot - start - philo.last_meal > t_td) {
                tty.printk("{} {} died\n", .{ time_since_boot - start, philo.id });
                end_of_simulation = true;
                eos_mutex.release();
                break :b true;
            }
            eos_mutex.release();
        }
        // @import("../task/sleep.zig").usleep(500) catch {};
        _ = scheduler.schedule();
    };

    const current_pid = task.getpid();
    for (philosophers) |philo| {
        var stat: wait.Status = undefined;
        _ = wait.wait(
            current_pid,
            .CHILD,
            &stat,
            null,
            .{},
        ) catch ft.log.warn("Failed to wait for philosopher {}", .{philo.id});
    }

    tty.printk("End of simulation {}\n", .{status});
}
