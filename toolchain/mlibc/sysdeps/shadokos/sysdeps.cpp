#include <abi-bits/errno.h>
#include <abi-bits/vm-flags.h>
#include <bits/ensure.h>
#include <bits/syscall.h>
#include <mlibc/all-sysdeps.hpp>
#include <stdint.h>
#include <string.h>

namespace {

inline long sc(long n) { return __shadokos_syscall0(n); }
template <typename A0> long sc(long n, A0 a0) { return __shadokos_syscall1(n, (long)a0); }
template <typename A0, typename A1> long sc(long n, A0 a0, A1 a1) {
	return __shadokos_syscall2(n, (long)a0, (long)a1);
}
template <typename A0, typename A1, typename A2> long sc(long n, A0 a0, A1 a1, A2 a2) {
	return __shadokos_syscall3(n, (long)a0, (long)a1, (long)a2);
}
template <typename A0, typename A1, typename A2, typename A3>
long sc(long n, A0 a0, A1 a1, A2 a2, A3 a3) {
	return __shadokos_syscall4(n, (long)a0, (long)a1, (long)a2, (long)a3);
}
template <typename A0, typename A1, typename A2, typename A3, typename A4>
long sc(long n, A0 a0, A1 a1, A2 a2, A3 a3, A4 a4) {
	return __shadokos_syscall5(n, (long)a0, (long)a1, (long)a2, (long)a3, (long)a4);
}
template <typename A0, typename A1, typename A2, typename A3, typename A4, typename A5>
long sc(long n, A0 a0, A1 a1, A2 a2, A3 a3, A4 a4, A5 a5) {
	return __shadokos_syscall6(n, (long)a0, (long)a1, (long)a2, (long)a3, (long)a4, (long)a5);
}

/* Only [-4095, -1] is an error: user addresses stay below 0xc0000000, so a
 * negative-looking mmap result is a valid pointer, not an errno. */
inline int sc_error(long r) {
	if (static_cast<unsigned long>(r) > static_cast<unsigned long>(-4096L))
		return static_cast<int>(-r);
	return 0;
}

constexpr long kMapAnonymous = 1 << 0;
constexpr long kMapPrivate = 0b01 << 1;
constexpr long kMapShared = 0b10 << 1;
constexpr long kMapFixed = 1 << 3;
constexpr long kMapNoreplace = 1 << 4;

long translate_map_flags(int flags) {
	long out = (flags & MAP_SHARED) ? kMapShared : kMapPrivate;
	if (flags & MAP_ANONYMOUS)
		out |= kMapAnonymous;
	if (flags & MAP_FIXED)
		out |= kMapFixed;
	return out;
}

} // namespace

namespace mlibc {

void Sysdeps<Exit>::operator()(int status) {
	sc(SYS_EXIT, status);
	__builtin_unreachable();
}

void Sysdeps<LibcLog>::operator()(const char *msg) {
	sc(SYS_WRITE, 2, msg, strlen(msg));
	sc(SYS_WRITE, 2, "\n", 1);
}

void Sysdeps<LibcPanic>::operator()() {
	sysdep<LibcLog>("!!! mlibc panic !!!");
	sysdep<Exit>(-1);
	__builtin_trap();
}

int Sysdeps<Isatty>::operator()(int) {
	// No file descriptor layer yet: everything is the tty.
	return 0;
}

int Sysdeps<Write>::operator()(int fd, void const *buf, size_t size, ssize_t *bytes_written) {
	long r = sc(SYS_WRITE, fd, buf, size);
	if (int e = sc_error(r))
		return e;
	*bytes_written = r;
	return 0;
}

int Sysdeps<TcbSet>::operator()(void *pointer) {
	long r = sc(SYS_SET_THREAD_AREA, pointer);
	if (int e = sc_error(r))
		return e;
	return 0;
}

int Sysdeps<AnonAllocate>::operator()(size_t size, void **pointer) {
	long r = sc(SYS_MMAP, nullptr, size, PROT_READ | PROT_WRITE, kMapAnonymous | kMapPrivate, -1, 0);
	if (int e = sc_error(r))
		return e;
	*pointer = reinterpret_cast<void *>(r);
	return 0;
}

int Sysdeps<AnonFree>::operator()(void *pointer, size_t size) {
	return sc_error(sc(SYS_MUNMAP, pointer, size));
}

int Sysdeps<VmMap>::operator()(void *hint, size_t size, int prot, int flags, int fd, off_t offset, void **window) {
	long r = sc(SYS_MMAP, hint, size, prot, translate_map_flags(flags), fd, offset);
	if (int e = sc_error(r))
		return e;
	*window = reinterpret_cast<void *>(r);
	return 0;
}

int Sysdeps<VmUnmap>::operator()(void *pointer, size_t size) {
	return sc_error(sc(SYS_MUNMAP, pointer, size));
}

int Sysdeps<VmProtect>::operator()(void *pointer, size_t size, int prot) {
	return sc_error(sc(SYS_MPROTECT, pointer, size, prot));
}

int Sysdeps<Seek>::operator()(int, off_t, int, off_t *) {
	// No file descriptor layer yet, nothing is seekable.
	return ESPIPE;
}

int Sysdeps<Close>::operator()(int fd) {
	auto ret = sc(SYS_CLOSE, fd);
	if (int e = sc_error(ret); e)
		return e;
	return 0;
}

int Sysdeps<Open>::operator()(const char *path, int flags, unsigned int mode, int *result)
{
	auto ret = sc(SYS_OPEN, path, flags, mode);
	if (int e = sc_error(ret); e)
		return e;
	*result = ret;
	return 0;
}

int Sysdeps<Read>::operator()(int fd, void *buffer, size_t size, ssize_t *result)
{
	auto ret = sc(SYS_READ, fd, buffer, size);
	if (int e = sc_error(ret); e)
		return e;
	*result  = ret;
	return 0;
}

int Sysdeps<Recvfrom>::operator()(int, void *, size_t, int, struct sockaddr *, socklen_t *, ssize_t *) {
	return ENOSYS;
}

int Sysdeps<ClockGet>::operator()(int, time_t *secs, long *nanos) {
	// No clock syscall yet
	*secs = 0;
	*nanos = 0;
	return 0;
}

// Single-threaded for now: report a spurious wake-up instead of blocking
int Sysdeps<FutexWait>::operator()(int *, int, timespec const *) { return 0; }

int Sysdeps<FutexWake>::operator()(int *, bool) { return 0; }

uid_t Sysdeps<GetUid>::operator()() { return sc_error(sc(SYS_GETUID)); }
uid_t Sysdeps<GetEuid>::operator()() { return sc_error(sc(SYS_GETEUID)); }
gid_t Sysdeps<GetGid>::operator()() { return sc_error(sc(SYS_GETGID)); }
gid_t Sysdeps<GetEgid>::operator()() { return sc_error(sc(SYS_GETEGID)); }
pid_t Sysdeps<GetPid>::operator()() { return sc_error(sc(SYS_GETPID)); }
pid_t Sysdeps<GetPpid>::operator()() { return sc_error(sc(SYS_GETPPID)); }

int Sysdeps<GetCwd>::operator()(char *buf, size_t size) {
	auto ret = sc(SYS_GETCWD, buf, size);
	if (int e = sc_error(ret); e) {
		return e;
	}
	return 0;
}

int Sysdeps<Chdir>::operator()(const char *path) {
	auto ret = sc(SYS_CHDIR, path);
	if (int e = sc_error(ret); e)
		return e;
	return 0;
}

int Sysdeps<Sigaction>::operator()(int signum, const struct sigaction *act,
struct sigaction *oldact) {
	auto ret = sc(SYS_SIGACTION, signum, act, oldact);
	if (int e = sc_error(ret); e)
		return e;
	return 0;
}

int Sysdeps<Pipe>::operator()(int *fds, int) {
	auto ret = sc(SYS_PIPE, fds);
	if (int e = sc_error(ret); e)
		return e;
	return 0;
}

int Sysdeps<Fcntl>::operator()(int fd, int request, va_list , int *result) {
	auto ret = sc(SYS_FCNTL, fd, request);
	if (int e = sc_error(ret); e)
		return e;
	*result = ret;
	return 0;
}

int Sysdeps<Dup>::operator()(int fd, int flags, int *newfd) {
	__ensure(!flags);
	auto ret = sc(SYS_DUP, fd);
	if (int e = sc_error(ret); e)
		return e;
	*newfd = ret;
	return 0;
}

int Sysdeps<Dup2>::operator()(int fd, int, int newfd) {
	auto ret = sc(SYS_DUP2, fd, newfd);
	if(int e = sc_error(ret); e)
		return e;
	return 0;
}


int Sysdeps<Fork>::operator()(pid_t *child) {
	auto ret = sc(SYS_FORK);
	if (int e = sc_error(ret); e)
			return e;
	*child = ret;
	return 0;
}

int Sysdeps<Execve>::operator()(const char *path, char *const argv[], char *const envp[]) {
	auto ret = sc(SYS_EXECVE, path, argv, envp);
	if (int e = sc_error(ret); e)
		return e;
	return 0;
}

int Sysdeps<Ioctl>::operator()(int fd, unsigned long request, void *arg, int *result) {
	auto ret = sc(SYS_IOCTL, fd, request, arg);
	if (int e = sc_error(ret); e)
		return e;
	if (result)
		*result = ret;
	return 0;
}

int Sysdeps<Stat>::operator()(fsfd_target fsfdt, int fd, const char *path, int flags, struct stat *statbuf) {
	__ensure(!flags);
	__ensure(fsfdt == fsfd_target::path);
	auto ret = sc(SYS_STAT, path, statbuf);
	if (int e = sc_error(ret); e)
		return e;
	return 0;
}

int Sysdeps<Waitpid>::operator()(pid_t pid, int *status, int flags, struct rusage *ru, pid_t *ret_pid) {
	__ensure(!ru);
	auto ret = sc(SYS_WAITPID, pid, status, flags);
	if (int e = sc_error(ret); e)
			return e;
	*ret_pid = ret;
	return 0;
}

int Sysdeps<Tcgetattr>::operator()(int fd, struct termios *attr) {
	auto ret = sc(SYS_TCGETATTR, fd, attr);
	if (int e = sc_error(ret); e)
		return e;
	return 0;
}

int Sysdeps<Tcsetattr>::operator()(int fd, int optional_action, const struct termios *attr) {
	__ensure(optional_action);

	auto ret = sc(SYS_TCSETATTR, fd, 0, attr);
	if (int e = sc_error(ret); e)
		return e;
	return 0;
}


// int Sysdeps<Tcsendbreak>::operator()(int fd, int) {
// 	auto ret = sc(SYS_IOCTL, fd, TCSBRK, 0);
// 	if (int e = sc_error(ret); e)
// 		return e;
// 	return 0;
// }
//
// int Sysdeps<Tcflow>::operator()(int fd, int action) {
// 	auto ret = sc(SYS_IOCTL, fd, TCXONC, action);
// 	if (int e = sc_error(ret); e)
// 		return e;
// 	return 0;
// }
//
// int Sysdeps<Tcflush>::operator()(int fd, int queue) {
// 	auto ret = sc(SYS_IOCTL, fd, TCFLSH, queue);
// 	if (int e = sc_error(ret); e)
// 		return e;
// 	return 0;
// }
//
// int Sysdeps<Tcdrain>::operator()(int fd) {
// 	auto ret = sc(SYS_IOCTL, fd, TCSBRK, 1);
// 	if (int e = sc_error(ret); e)
// 		return e;
// 	return 0;
// }


int Sysdeps<SetSid>::operator()(pid_t *sid) {
	auto ret = sc(SYS_SETSID);
	if (int e = sc_error(ret); e)
		return e;
	*sid = ret;
	return 0;
}

} // namespace mlibc