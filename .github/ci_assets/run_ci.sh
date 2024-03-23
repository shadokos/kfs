#!/bin/bash

docker build . -f DockerCI -t qemu
docker run --rm --name qemu -p 4444:4444 -w /build -v ./:/build:rw -d qemu \
	qemu-system-i386 -cdrom kfs.iso -nographic -serial tcp::4444,server,nowait && sleep 5
python3 ci_test.py
ret=$?
docker stop qemu 1>/dev/null 2>/dev/null
exit $ret