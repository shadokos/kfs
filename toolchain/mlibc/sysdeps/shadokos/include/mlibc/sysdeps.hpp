#pragma once

#include <mlibc/sysdep-signatures.hpp>

namespace mlibc {

struct ShadokosSysdepTags :
	LibcPanic,
	LibcLog,
	Isatty,
	Write,
	TcbSet,
	AnonAllocate,
	AnonFree,
	Seek,
	Exit,
	Close,
	FutexWake,
	FutexWait,
	Read,
	Open,
	VmMap,
	VmUnmap,
	VmProtect,
	ClockGet,
	GetPid,
	GetPpid,
	GetUid,
	GetEuid,
	GetGid,
	GetEgid,
	GetCwd,
	Chdir,
	Sigaction,
	Pipe,
	Fcntl,
	Ioctl,
	Stat,
	Dup2,
	Dup,
	Execve,
	Fork,
	Waitpid,
	Tcgetattr,
	Tcsetattr,
    SetSid,
	GetResgid,
	GetResuid,
	SetResgid,
	SetResuid,
	SetEgid,
	SetEuid,
	SetGid,
	SetUid,
    // Tcdrain,
    // Tcflush,
    // Tcflow,
    // Tcsendbreak,
	// Not implemented (ENOSYS), but the posix/bsd sources dispatch to
	// them at compile time so the tags have to exist.
	Recvfrom


//	GetEuid,
//	GetResuid,
//	SetResuid,
//	GetGid,
//	GetEgid,
//	GetResgid,
//	SetResgid,
//	SetReuid,
//	SetRegid,
//	SetUid,
//	SetEuid,
//	SetGid,
//	SetEgid,
//	SetGroups,
//	GetGroups,
//	GetTid,
//	GetPpid,
//	GetPgid,
//	SetPgid,
//	SetSid,
//	GetSid,
{};

template<typename Tag>
using Sysdeps = SysdepOf<ShadokosSysdepTags, Tag>;

struct SysdepTraits {
	static constexpr bool usesRtNetlink = false;
};

} // namespace mlibc
