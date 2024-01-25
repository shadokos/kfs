FROM alpine

RUN echo 'https://dl-cdn.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories

RUN apk update

RUN apk add zig make grub mtools xorriso grub-bios grub-dev grub-efi xz
