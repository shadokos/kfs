#!/bin/dash

export PATH=/bin

mount /dev .virtual devfs

echo bonjour

setsid /bin/dash /etc/init2.sh
