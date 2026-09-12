#!/bin/dash

export PATH=/bin
export SHLVL=0

mount /dev .virtual devfs

echo bonjour

exec </dev/tty0 >>/dev/tty0 2>>/dev/tty0

/bin/dash
#setsid /bin/dash /etc/init2.sh
