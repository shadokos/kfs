#!/bin/sh

BINUTILS_VERSION=2.47
GCC_VERSION=16.2.0

BINUTILS_URL="https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VERSION.tar.xz"
GCC_URL="https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/gcc-$GCC_VERSION.tar.xz"

BINUTILS_BASE="binutils-$BINUTILS_VERSION"
GCC_BASE="gcc-$GCC_VERSION"

BINUTILS_PATCH="patch_binutils.diff"
GCC_PATCH="patch_gcc.diff"

TARGET=i686-shadokos

[ -z "$TOOLCHAIN_DIR" -o -z "$SYSROOT_DIR" ] && {
	echo please setup TOOLCHAIN_DIR AND SYSROOT_DIR >&2
	exit 1
}

download_and_patch() {
	URL=$1
	BASE=$2
	PATCH=$3
	curl $URL -o $BASE.tar.xz
	tar xf $BASE.tar.xz $BASE
	patch -p1 -d $BASE < $PATCH
}

build_binutils() (
	download_and_patch $BINUTILS_URL $BINUTILS_BASE $BINUTILS_PATCH

	cd $BINUTILS_BASE/
	mkdir build
	cd build
	../configure \
		--target=$TARGET \
		--prefix=/usr \
		--with-sysroot="${SYSROOT_DIR}" \
		--disable-werror \
		--enable-default-execstack=no
	make -j$(nproc)
	DESTDIR="${TOOLCHAIN_DIR}" make install
)


build_gcc() (
	export PATH=$TOOLCHAIN_DIR/usr/bin:$PATH
	download_and_patch $GCC_URL $GCC_BASE $GCC_PATCH
	cd $GCC_BASE/
	mkdir build
	cd build
	../configure \
		--target=$TARGET \
		--prefix=/usr \
		--with-sysroot="${SYSROOT_DIR}" \
		--enable-languages=c,c++ \
		--enable-threads=posix \
		--disable-multilib \
		--enable-shared \
		--enable-host-shared 
	make -j$(nproc) all-gcc all-target-libgcc
	DESTDIR="${TOOLCHAIN_DIR}" make install-gcc install-target-libgcc
)

export SYSROOT=$SYSROOT_DIR

$@

