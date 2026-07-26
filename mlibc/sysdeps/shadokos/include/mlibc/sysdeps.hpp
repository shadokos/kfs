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
	// Not implemented (ENOSYS), but the posix/bsd sources dispatch to
	// them at compile time so the tags have to exist.
	Recvfrom,
	Dup2
{};

template<typename Tag>
using Sysdeps = SysdepOf<ShadokosSysdepTags, Tag>;

struct SysdepTraits {
	static constexpr bool usesRtNetlink = false;
};

} // namespace mlibc
