#!/bin/dash

export PATH=/bin

mount /dev .virtual devfs

exec </dev/tty0 >>/dev/tty0 2>>/dev/tty0

echo bonjour

#setsid /bin/dash /etc/init2.sh
