sysdep_supported_options = {
	'posix': true,
	'glibc': true,
	'bsd': true,
}

rtld_include_dirs += include_directories('include')
libc_include_dirs += include_directories('include')

if not headers_only
	# The low-level glue (syscall trampoline, crt1) is written in Zig and
	# compiled with the native zig compiler; only the sysdeps declaration
	# layer stays in C++ (mlibc's Sysdeps<Tag> template specializations).
	zig = find_program('zig')
	# -mcpu=i686: no SSE, the kernel does not enable CR4.OSFXSR.
	zig_build_obj = [
		zig, 'build-obj',
		'-target', 'x86-freestanding-none',
		'-mcpu=i686',
		'-O', 'ReleaseSmall',
		'-femit-bin=@OUTPUT@',
		'@INPUT@',
	]

	syscall_o = custom_target('shadokos-syscall',
		command: zig_build_obj,
		input: 'syscall.zig',
		output: 'syscall.o',
	)

	libc_sources += [ files('entry.cpp', 'sysdeps.cpp'), syscall_o ]
	rtld_sources += [ files('sysdeps.cpp'), syscall_o ]

	crt = custom_target('crt1',
		build_by_default: true,
		command: zig_build_obj,
		input: 'crt1.zig',
		output: 'crt1.o',
		install: true,
		install_dir: get_option('libdir')
	)
endif

if not no_headers
	install_headers(
		'include/abi-bits/auxv.h',
		'include/abi-bits/blkcnt_t.h',
		'include/abi-bits/blksize_t.h',
		'include/abi-bits/clockid_t.h',
		'include/abi-bits/dev_t.h',
		'include/abi-bits/errno.h',
		'include/abi-bits/fcntl.h',
		'include/abi-bits/gid_t.h',
		'include/abi-bits/ino_t.h',
		'include/abi-bits/limits.h',
		'include/abi-bits/mode_t.h',
		'include/abi-bits/nlink_t.h',
		'include/abi-bits/pid_t.h',
		'include/abi-bits/seek-whence.h',
		'include/abi-bits/signal.h',
		'include/abi-bits/stat.h',
		'include/abi-bits/uid_t.h',
		'include/abi-bits/vm-flags.h',
		'include/abi-bits/wait.h',
		'include/abi-bits/riscv-hwprobe.h',
		'include/abi-bits/sigevent.h',
		'include/abi-bits/sigval.h',
		'include/abi-bits/sa_family_t.h',
		'include/abi-bits/sockaddr_storage.h',
		'include/abi-bits/sig-limits.h',
		'include/abi-bits/suseconds_t.h',
		'include/abi-bits/access.h',
		'include/abi-bits/socklen_t.h',
		'include/abi-bits/socket.h',
		'include/abi-bits/poll.h',
		'include/abi-bits/resource.h',
		'include/abi-bits/in.h',
		'include/abi-bits/rlim_t.h',
		'include/abi-bits/utsname.h',
		'include/abi-bits/fd_set.h',
		'include/abi-bits/sem.h',
		'include/abi-bits/time.h',
		'include/abi-bits/ipc.h',
		'include/abi-bits/statvfs.h',
		'include/abi-bits/fsblkcnt_t.h',
		'include/abi-bits/fsfilcnt_t.h',
		'include/abi-bits/shm.h',
		'include/abi-bits/termios.h',
		'include/abi-bits/msg.h',
		'include/abi-bits/mqueue.h',
		'include/abi-bits/utmp-defines.h',
		'include/abi-bits/utmpx.h',
		'include/abi-bits/sigset_t.h',
		'include/abi-bits/aio.h',
		'include/abi-bits/epoll.h',
		'include/abi-bits/inotify.h',
		'include/abi-bits/ioctls.h',
		'include/abi-bits/packet.h',
		'include/abi-bits/ptrace.h',
		'include/abi-bits/random.h',
		'include/abi-bits/reboot.h',
		'include/abi-bits/route.h',
		'include/abi-bits/statfs.h',
		'include/abi-bits/statx.h',
		'include/abi-bits/vt.h',
		'include/abi-bits/xattr.h',
		'include/abi-bits/sched_param.h',
		subdir: 'abi-bits',
		follow_symlinks: true
	)
endif
