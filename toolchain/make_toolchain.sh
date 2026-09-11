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
		--enable-host-shared \
		--with-gmp-lib=/nix/store/km81slwkcc82dbwywl10gpffjb78g6ni-gmp-with-cxx-6.3.0/lib \
		--with-gmp-include=/nix/store/mml8yn060rz4krfdcqpqy435imx3x2k3-gmp-with-cxx-6.3.0-dev/include \
		--with-mpfr-lib=/nix/store/d6n8cwsfwaas0x107zc3z1dzhyr3mca0-mpfr-4.2.2/lib \
		--with-mpfr-include=/nix/store/yw6c77xnzb501c0j59g4r3gfvxcvjz1s-mpfr-4.2.2-dev/include \
		--with-mpc=/nix/store/lihsv1sjl1xrpp7iwb4bf99alaqgr8dh-libmpc-1.3.1
	make -j$(nproc) all-gcc all-target-libgcc
	DESTDIR="${TOOLCHAIN_DIR}" make install-gcc install-target-libgcc
)

make libc-headers
build_binutils
build_gcc
make libc

