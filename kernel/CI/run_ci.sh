#!/bin/bash

cd $(dirname $0)/..

docker build CI -t qemu
docker run --rm --name qemu -p 4444:4444 -w /build -v ./:/build:rw -d \
  qemu -cdrom kfs.iso -nographic -serial tcp::4444,server,nowait && sleep 5
python3 CI/ci_commands.py
ret=$?
docker stop qemu 1>/dev/null 2>/dev/null
exit $ret