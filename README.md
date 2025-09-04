<p align=center><img src="https://github.com/user-attachments/assets/3d0842b6-4044-4da8-aebd-0c8e05b578a7" width="350px"/></p>
<h1 align=center>
  <sup><sub>
    Experimental i386 UNIX-like kernel written entirely in
  </sub></sup>
  <a href="https://ziglang.org/">
    <img src="https://github.com/user-attachments/assets/5e13dfe0-8d15-415c-b981-95ac5a351080" width="75px" />
  </a>
    <br><br>
  <div align=left>Overview</div>
</h1>

ShadokOS is a small hobby / experimental x86 Unix-like kernel implemented in the Zig programming language.  
The repository is developed and maintained by [@jgiron42](https://github.com/jgiron42) and [@riblanc](https://github.com/riblanc) as an exploratory engineering effort to study and build the components of a kernel from first principles.  
This project is a place to iterate on system-level design, experiment with low-level implementation techniques, and exercise careful engineering practices.


> /!\ **Disclaimer**  
While practical and hands-on, ShadokOS is experimental and don't pretend to compete with any established kernels nor to deliver a production-ready kernel.
Therefore, we are not responsible for any damage or data loss that may occur from running this kernel on real hardware.

# Quickstart

As we are using linux for development, the instructions below assume a Linux host system.

### Prerequisites
At least the following tools are required:
- QEMU (for running the kernel locally)
- GNU make
- Grub 2 (if using the GRUB ISO flow) with eventually grub-pc-bin and grub2-common on Debian-based distros

By default, the build system will automatically download Limine (default bootloader) and the necessary Zig toolchain for you if not found locally.

### Build / Run

To build the kernel and run it with QEMU, you can simply run:
~~~bash
make run
~~~

The `Release-Safe` optimization mode is used by default.  
You can also specify a different optimization mode by using one of the following targets:
- `Debug`: useful for development, debug symbols and logs, no optimizations, and extra runtime checks.<br><br>
  ~~~bash
  make debug run
  ~~~
- `Release-safe`: optimized build, with runtime checks.<br><br>
  ~~~bash
  make release run
  ~~~
- `Release-fast`: optimized build for performance, no runtime checks.<br><br>
  ~~~bash
  make fast run
  ~~~

# Status & Roadmap

The project is structured around a modular roadmap, where each stage focuses on building a fundamental subsystem of the kernel.  
Completed milestones (KFS, **K**_ernel_ **F**_rom_ **S**_cratch_) are checked off.

* [x] **KFS 1** — Bootable kernel image, basic kernel library, VGA screen output with `Hello World`, scrolling, cursor, color support, minimal `printf`/`printk`, keyboard input, multi-screen handling.
  <br><br>
* [x] **KFS 2** — Global Descriptor Table (GDT), kernel/user segmentation, a minimal command-line interface, and simple builtins commands (reboot, halt, stack print).
  <br><br>
* [x] **KFS 3** — Core memory management: paging, kernel/user address spaces, allocation helpers (`kmalloc`/`kfree`, `vmalloc`/`vfree`), kernel panic handling, memory dump/debug tools.
  <br><br>
* [x] **KFS 4** — Interrupt Descriptor Table (IDT), basic signal/interrupt handling, register/stack management, keyboard interface and line input helpers.
  <br><br>
* [x] **KFS 5** — Process structures, multitasking (preemptive foundations), and syscall groundwork (fork, wait, exit, signals, memory mapping).
  <br><br>
* [ ] **KFS 6** — Filesystem support: block device read/write, ext2 parsing, root directory operations and commands (`cat`, `cd`, `pwd`), with optional features like multi-partition support and user accounts.
  <br><br>
* [ ] **KFS 7** — Full syscall interface and Unix-like environment: user accounts, IPC mechanisms, hierarchical filesystem, optional multi-TTY support and user-specific environments.
  <br><br>
* [ ] **KFS 8** — Kernel module interface: support for dynamically loadable modules, safe callbacks, isolated memory regions, and example modules (keyboard, timer).
  <br><br>
* [ ] **KFS 9** — ELF loader and runtime module execution with syscall integration.
  <br><br>
* [ ] **KFS 10** — Userland environment: minimal libc, POSIX-style shell, core binaries in `/bin/*`, with optional installer and customization support.

The roadmap is designed so that each step builds on the last, allowing experimentation and iteration without losing sight of the bigger system.


# License

ShadokOS is licensed under the GNU General Public License v3 (GPLv3).  
You are free to use, modify, and redistribute it under the terms of this license,
but any derived work must also be made available under GPLv3, and the original authors must be credited.

See [LICENSE](./LICENSE) for more details.

