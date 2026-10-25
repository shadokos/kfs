FROM alpine

RUN echo 'https://dl-cdn.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories

RUN apk update
RUN apk add qemu-img qemu-system-i386

EXPOSE 4444
ENTRYPOINT ["qemu-system-i386"]
