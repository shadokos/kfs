# ShadokOS

Shadokos is a UNIX-like kernel for i386 written entirely in [Zig](https://ziglang.org/)

## features

### Terminal

- [X] VGA text mode driver
- [X] PS2 driver
- [X] mostly POSIX I/O interface with termios configuration
- [X] vt100 escape codes
- [X] virtual scroll
- [X] themes from [gogh](https://gogh-co.github.io/Gogh/)
- [ ] signal distribution

### Memory system

- [X] Higher half kernel
- [X] Buddy allocators for page frame allocation
- [X] on-page-fault mapping
- [X] fast virtual space allocation using double-key AVLs
- [X] virtual page allocation with multiple strategies
- [X] multiple object allocators
  - [X] slab allocator
  - [X] multipool allocator (based on slab allocator)
  - [X] page grained allocator
- [X] allocation fuzzing using multiple strategies
- [ ] copy on write

### Multitasking

- [X] task switching
- [X] basic scheduler
- [X] virtual space switching
- [X] process table
- [X] signal delivery system
- [ ] signal execution
- [ ] advanced scheduler
- [ ] syscall table

### Filesystem

- [ ] IDE driver
- [ ] file mapping
- [ ] ext2 driver

### syscall api

### kernel modules

### ELF execution

### Testing

- [X] Serial port interface
- [X] kernel mode CLI
- [X] memory system CI
- [X] build CI
- [X] linter CI

