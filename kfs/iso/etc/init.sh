#!/bin/sh

export PATH=/bin

mount #-t devfs /dev

exec </dev/tty0 >/dev/tty0 2>/dev/tty0

echo bonjour
set -i
exec
