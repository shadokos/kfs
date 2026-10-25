FROM debian:trixie AS base

RUN apt update -y && apt upgrade -y 
RUN apt install -y libmpfr-dev libgmp-dev libmpc-dev make curl autoconf meson git wget autoconf2.69

FROM base AS build

RUN mkdir /src
WORKDIR /src

ARG GCC_CACHE_ID="shadokos-gcc-build"

ENV TOOLCHAIN_PREFIX=/opt/cross
ENV TARGET_PREFIX=/usr
ENV SYSROOT=/sysroot

ENV GCC_DIR="/src/gcc"
ENV BINUTILS_DIR="/src/binutils"
ENV MLIBC_DIR="/src/mlibc"
ENV ZIG_DIR="/zig"

RUN mkdir -p $ZIG_DIR $GCC_DIR $BINUTILS_DIR $MLIBC_DIR $TOOLCHAIN_PREFIX $SYSROOT

ENV PATH=$PATH:$TOOLCHAIN_PREFIX/bin

FROM build AS zig

ARG TARGETARCH
ARG ZIG_VERSION=0.17.0

RUN case "$TARGETARCH" in \
      amd64) arch=x86_64 ;; \
      arm64) arch=aarch64 ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    ZIG_ARCHIVE="zig-$arch-linux-$ZIG_VERSION"; \
    curl -L https://ziglang.org/builds/$ZIG_ARCHIVE.tar.xz | \
      tar xJ -C $ZIG_DIR --strip-components=1

FROM build AS binutils

ARG BINUTILS_VERSION=2.47

ENV BINUTILS_URL="https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VERSION.tar.xz"

RUN curl -L $BINUTILS_URL | \
      tar xJ -C $BINUTILS_DIR --strip-components=1

ARG BINUTILS_PATCH="patch_binutils.diff"

COPY $BINUTILS_PATCH /src

RUN patch -p1 -d $BINUTILS_DIR < $BINUTILS_PATCH

ARG TARGET=i686-shadokos

RUN --mount=type=cache,sharing=private,id=shadokos-binutils-build,target=${BINUTILS_DIR}/build \
    cd $BINUTILS_DIR/build; \
	../configure \
		--target=$TARGET \
		--prefix=${TOOLCHAIN_PREFIX} \
		--with-sysroot="${SYSROOT}" \
		--disable-werror \
		--enable-default-execstack=no; \
	make -j$(nproc); \
	make install

FROM build AS mlibc-headers

ARG MLIBC_VERSION="v7.0.0"

RUN curl -L https://github.com/managarm/mlibc/archive/refs/tags/$MLIBC_VERSION.tar.gz | \
      tar xz -C $MLIBC_DIR --strip-components=1

ARG MLIBC_PATCH="patch_mlibc.diff"

COPY $MLIBC_PATCH /src

RUN patch -p1 -d $MLIBC_DIR < $MLIBC_PATCH

COPY shadokos_sysdeps $MLIBC_DIR/sysdeps/shadokos
COPY shadokos-i686.cross  $MLIBC_DIR/

RUN	meson setup \
		--cross-file $MLIBC_DIR/shadokos-i686.cross \
		--prefix=${TARGET_PREFIX} \
		-Dheaders_only=true \
		 -Dposix_option=enabled \
		mlibc-build/headers mlibc

RUN DESTDIR=${SYSROOT} ninja -C mlibc-build/headers install

FROM binutils AS gcc

ARG GCC_VERSION=16.2.0

ENV GCC_URL="https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/gcc-$GCC_VERSION.tar.xz"

RUN curl -L $GCC_URL | \
      tar xJ -C $GCC_DIR --strip-components=1

ARG GCC_PATCH="patch_gcc.diff"
COPY $GCC_PATCH /src
RUN patch -p1 -d $GCC_DIR < $GCC_PATCH

COPY --from=mlibc-headers $SYSROOT $SYSROOT

RUN --mount=type=cache,sharing=locked,id=${GCC_CACHE_ID},target=${GCC_DIR}/build \
    cd $GCC_DIR/build; \
    ../configure \
        --target=$TARGET \
        --prefix=${TOOLCHAIN_PREFIX} \
        --with-sysroot="${SYSROOT}" \
        --enable-languages=c,c++ \
        --enable-threads=posix \
        --disable-multilib \
        --enable-shared \
        --enable-host-shared; \
    make -j$(nproc) all-gcc all-target-libgcc; \
    make install-gcc install-target-libgcc

FROM gcc AS libs

#COPY --from=gcc "${TOOLCHAIN_PREFIX}" ${TOOLCHAIN_PREFIX}
COPY --from=zig $ZIG_DIR $ZIG_DIR
ENV PATH=$ZIG_DIR:$PATH

COPY --from=mlibc-headers $MLIBC_DIR $MLIBC_DIR

RUN meson setup \
        --cross-file $MLIBC_DIR/shadokos-i686.cross \
        --prefix=${TARGET_PREFIX} \
        -Ddefault_library=static \
        -Dno_headers=true \
        -Dlibgcc_dependency=false \
         -Dposix_option=enabled \
        mlibc-build/libc mlibc

RUN ninja -C mlibc-build/libc

RUN DESTDIR=${SYSROOT} ninja -C mlibc-build/libc install

RUN --mount=type=cache,sharing=locked,id=${GCC_CACHE_ID},target=${GCC_DIR}/build \
	(cd $GCC_DIR/libstdc++-v3; autoconf2.69); \
	cd $GCC_DIR/build; \
	make -j$(nproc) all-target-libstdc++-v3; \
	make install-target-libstdc++-v3


FROM base

ENV TOOLCHAIN_PREFIX=/opt/cross
ENV SYSROOT=/sysroot
ENV ZIG_DIR=/zig
ENV TARGET_PREFIX=/usr

COPY --from=libs ${TOOLCHAIN_PREFIX} ${TOOLCHAIN_PREFIX}
COPY --from=libs ${SYSROOT} ${SYSROOT}
COPY --from=zig $ZIG_DIR $ZIG_DIR

ENV PATH=${TOOLCHAIN_PREFIX}/bin:$ZIG_DIR:$PATH

ENV CROSS_COMPILE=i686-shadokos-
ENV CC=i686-shadokos-gcc
ENV CXX=i686-shadokos-g++
ENV AS=i686-shadokos-as
ENV LD=i686-shadokos-ld
ENV AR=i686-shadokos-ar
ENV RANLIB=i686-shadokos-ranlib
ENV NM=i686-shadokos-nm
ENV STRIP=i686-shadokos-strip
ENV OBJCOPY=i686-shadokos-objcopy
ENV OBJDUMP=i686-shadokos-objdump
ENV READELF=i686-shadokos-readelf
ENV PKG_CONFIG_SYSROOT_DIR=${SYSROOT}
ENV PKG_CONFIG_LIBDIR=${SYSROOT}${TARGET_PREFIX}/lib/pkgconfig:${SYSROOT}${TARGET_PREFIX}/share/pkgconfig
ENV CC_FOR_BUILD=gcc
#ENV CMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_PREFIX}/i686-shadokos.cmake

RUN mkdir /mount
WORKDIR /mount

CMD i686-shadokos-gcc
