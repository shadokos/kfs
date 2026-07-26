#include <assert.h>
#include <locale.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

#define TEST(loc, s1, s2, cmp) do { \
	int res = wcscoll_l(s1, s2, loc); \
	fprintf(stderr, "Comparing '%ls' vs '%ls': result = %d\n", s1, s2, res); \
	assert(res cmp); \
} while(0);

int main() {
	setlocale(LC_ALL, "C.utf8");

	locale_t german = newlocale(LC_COLLATE_MASK, "de_DE.utf8", (locale_t)0);
	assert(german);
	locale_t french = newlocale(LC_COLLATE_MASK, "fr_FR.utf8", (locale_t)0);
	assert(french);
	locale_t c = newlocale(LC_COLLATE_MASK, "C", (locale_t)0);
	assert(c);

	TEST(german, L"Aal", L"Ära", == -219);
	TEST(german, L"Ära", L"Bär", == -13);
	TEST(german, L"Müller", L"Müller", == 0);
	TEST(german, L"abc", L"ABC", == -5);
	TEST(german, L"essen", L"Essen", == -5);
	TEST(german, L"co-op", L"coop", == -9800);
	TEST(german, L"co\u200Bop", L"co\u200B\u200B\u200Bop", == 10207);
	TEST(german, L"\u212B", L"\u00c5", == 1);
	TEST(german, L"😁", L"🙂", == -65);
	TEST(german, L"😁", L"🤕", == -584);
	TEST(german, L"😁", L"ß", == -1);

	TEST(french, L"cote", L"côte", == -7);
	TEST(french, L"ete", L"été", == -4);

	TEST(c, L"Aal", L"Ära", == -1);
	TEST(c, L"Ära", L"Bär", == 1);
	TEST(c, L"Müller", L"Müller", == 0);
	TEST(c, L"abc", L"ABC", == 1);
	TEST(c, L"essen", L"Essen", == 1);
	TEST(c, L"co-op", L"coop", == -1);
	TEST(c, L"co\u200Bop", L"co\u200B\u200B\u200Bop", == -1);
	TEST(c, L"\u212B", L"\u00c5", == 1);
	TEST(c, L"😁", L"🙂", == -1);
	TEST(c, L"😁", L"🤕", == -1);
	TEST(c, L"😁", L"ß", == 1);

	freelocale(german);
	freelocale(french);
	freelocale(c);

	return 0;
}
