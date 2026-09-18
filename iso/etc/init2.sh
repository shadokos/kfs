#!/bin/dash

exec <$1 >>$1 2>>$1

/bin/busybox --install -s
export PATH=$PATH:/usr/bin

stty cooked
echo $1 "($$)"
exec dash -i