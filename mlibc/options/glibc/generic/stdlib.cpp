#include <mlibc/locale.hpp>
#include <mlibc/strtol.hpp>
#include <stdlib.h>

int rpmatch(const char *resp) {
	if(!resp || resp[0] == '\0')
		return -1;
	if(resp[0] == 'y' || resp[0] == 'Y')
		return 1;
	if(resp[0] == 'n' || resp[0] == 'N')
		return 0;
	return -1;
}

long strtol_l(const char *__restrict string, char **__restrict end, int base, locale_t loc) {
	auto l = static_cast<mlibc::localeinfo *>(loc);
	return mlibc::stringToInteger<long, char>(string, end, base, l);
}

long long strtoll_l(const char *__restrict string, char **__restrict end, int base, locale_t loc) {
	auto l = static_cast<mlibc::localeinfo *>(loc);
	return mlibc::stringToInteger<long long, char>(string, end, base, l);
}

unsigned long strtoul_l(const char *__restrict string, char **__restrict end, int base, locale_t loc) {
	auto l = static_cast<mlibc::localeinfo *>(loc);
	return mlibc::stringToInteger<unsigned long, char>(string, end, base, l);
}

unsigned long long strtoull_l(const char *__restrict string, char **__restrict end, int base, locale_t loc) {
	auto l = static_cast<mlibc::localeinfo *>(loc);
	return mlibc::stringToInteger<unsigned long long, char>(string, end, base, l);
}
