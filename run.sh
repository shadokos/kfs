#!/bin/sh -e

make -C kernel build
make -C userspace

rm iso/bin/*
cp userspace/bin/* iso/bin
ln -s iso/bin/dash iso/bin/sh
mkfs -F -t ext2 -U 8581277f-6f63-447a-8d0c-347e180d2466 -d iso fs.iso 100000


# COM1 on the terminal. signal=off keeps Ctrl-C for the guest instead of
# letting it kill qemu, which is what makes /dev/ttyS0 usable as a terminal.
# Repeat -serial to give the kernel more ports to probe.
QEMU_SERIAL="-chardev stdio,id=serial0,signal=off -serial chardev:serial0"

qemu-system-i386 -hda kernel/kfs.iso -hdb fs.iso #$QEMU_SERIAL
