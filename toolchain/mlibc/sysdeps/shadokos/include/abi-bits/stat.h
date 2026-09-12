#ifndef _ABIBITS_STAT_H
#define _ABIBITS_STAT_H

#include <abi-bits/uid_t.h>
#include <abi-bits/gid_t.h>
#include <bits/off_t.h>
#include <abi-bits/mode_t.h>
#include <abi-bits/dev_t.h>
#include <abi-bits/ino_t.h>
#include <abi-bits/blksize_t.h>
#include <abi-bits/blkcnt_t.h>
#include <abi-bits/nlink_t.h>
#include <bits/ansi/time_t.h>
#include <bits/ansi/timespec.h>
#include <stdint.h>

#define S_IFMT 0x0F000
#define S_IFBLK 0x06000
#define S_IFCHR 0x02000
#define S_IFIFO 0x01000
#define S_IFREG 0x08000
#define S_IFDIR 0x04000
#define S_IFLNK 0x0A000
#define S_IFSOCK 0x0C000

#define S_IRWXU 0700
#define S_IRUSR 0400
#define S_IWUSR 0200
#define S_IXUSR 0100
#define S_IRWXG 070
#define S_IRGRP 040
#define S_IWGRP 020
#define S_IXGRP 010
#define S_IRWXO 07
#define S_IROTH 04
#define S_IWOTH 02
#define S_IXOTH 01
#define S_ISUID 04000
#define S_ISGID 02000
#define S_ISVTX 01000

#define S_IREAD  S_IRUSR
#define S_IWRITE S_IWUSR
#define S_IEXEC  S_IXUSR

#ifdef __cplusplus
extern "C" {
#endif

struct stat {
	uint32_t st_dev;
	uint32_t st_ino;
	mode_t st_mode;
	uint32_t st_nlink;
	uint32_t st_uid;
	uint32_t st_gid;
	//	dev_t st_rdev;
	//	dev_t __pad1;
	uint64_t st_size;
	//	blksize_t st_blksize;
	//	int __pad2;
	//	blkcnt_t st_blocks;
	struct timespec st_atim;
	struct timespec st_mtim;
	struct timespec st_ctim;
	//	int __pad3[2];
};

#if defined(_DEFAULT_SOURCE) || defined(_LARGEFILE64_SOURCE)
#define stat64 stat
#endif

#ifdef __cplusplus
}
#endif

#endif /* _ABIBITS_STAT_H */
