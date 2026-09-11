BINUTILS_VERSION=2.47
GCC_VERSION=16.2.0

BINUTILS_URL="https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz"
GCC_URL="https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz"

BINUTILS_BASE=binutils-${BINUTILS_VERSION}
GCC_BASE=gcc-${GCC_VERSION}

BINUTILS_PATCH=patch_binutils.diff
GCC_PATCH=patch_gcc.diff

all: ${BINUTILS_BASE} ${GCC_BASE}

${BINUTILS_BASE}: ${BINUTILS_BASE}.tar.xz ${BINUTILS_PATCH}
	tar xf $< ${BINUTILS_BASE}
	patch -p1 -d ${BINUTILS_BASE} < ${BINUTILS_PATCH}

${BINUTILS_BASE}.tar.xz:
	curl ${BINUTILS_URL} -o $@


: ${BINUTILS_BASE}

${GCC_BASE}: ${GCC_BASE}.tar.xz ${GCC_PATCH}
	tar xf $< ${GCC_BASE}
	patch -p1 -d ${GCC_BASE} < ${GCC_PATCH}

${GCC_BASE}.tar.xz:
	curl ${GCC_URL} -o $@


clean:
	rm -rf ${BINUTILS_BASE}.tar.xz ${BINUTILS_BASE}
	rm -rf ${GCC_BASE}.tar.xz ${GCC_BASE}
