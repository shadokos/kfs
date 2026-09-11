FROM debian

RUN apt update -y && apt upgrade -y 
RUN apt install -y libmpfr-dev libgmp-dev libmpc-dev make curl autoconf meson git wget 

ENV ZIG_ARCHIVE=zig-x86_64-linux-0.17.0-dev.2085+5e36170b5
RUN wget https://ziglang.org/builds/$ZIG_ARCHIVE.tar.xz
RUN tar xf $ZIG_ARCHIVE.tar.xz
ENV PATH=/$ZIG_ARCHIVE:$PATH

RUN mkdir /src
WORKDIR /src

ENV TOOLCHAIN_DIR=$PWD/toolchain
ENV SYSROOT_DIR=$PWD/sysroot
ENV SYSROOT=$SYSROOT_DIR

COPY mlibc /src/mlibc
COPY shadokos-i686.cross Makefile  /src
RUN make libc-headers

COPY patch_binutils.diff patch_gcc.diff make_toolchain.sh /src
RUN ./make_toolchain.sh build_binutils
RUN ./make_toolchain.sh build_gcc

ENV PATH=$TOOLCHAIN_DIR/usr/bin:$PATH

RUN make libc

RUN mkdir /mount

WORKDIR /mount

CMD i686-shadokos-gcc
