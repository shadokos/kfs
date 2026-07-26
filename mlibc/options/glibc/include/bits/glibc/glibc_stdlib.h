#ifndef _MLIBC_GLIBC_STDLIB_H
#define _MLIBC_GLIBC_STDLIB_H

#ifdef __cplusplus
extern "C" {
#endif

#include <mlibc-config.h>
#include <bits/posix/locale_t.h>

typedef int (*comparison_fn_t) (const void *__a, const void *__b);

#ifndef __MLIBC_ABI_ONLY

#if defined(_DEFAULT_SOURCE)
int rpmatch(const char *__resp);
#endif

#if defined(_GNU_SOURCE)

long strtol_l(const char *__restrict __string, char **__restrict __end, int __base, locale_t __loc);
long long strtoll_l(const char *__restrict __string, char **__restrict __end, int __base, locale_t __loc);
unsigned long strtoul_l(const char *__restrict __string, char **__restrict __end, int __base, locale_t __loc);
unsigned long long strtoull_l(const char *__restrict __string, char **__restrict __end, int __base, locale_t __loc);

#endif /* defined(_GNU_SOURCE) */

#endif /* !__MLIBC_ABI_ONLY */

#ifdef __cplusplus
}
#endif

#endif /* _MLIBC_GLIBC_STDLIB_H */
