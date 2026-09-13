#!/bin/dash

exec <$1 >>$1 2>>$1
stty cooked
echo $1 "($$)"
exec dash -i