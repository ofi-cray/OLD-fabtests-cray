#!/bin/bash

CS=$1
CMD="$2"
PROV=gni
IP=`/sbin/ifconfig |grep ipog -A 1 |grep 'inet addr'| awk '{print $2}' |tr -d 'addr:'`

CMD=`echo $CMD | sed -e "s/LOCAL_IP_ADDR/$IP/g"`

if [ $CS -eq 0 ]; then
	echo "Running: $CMD &"
	$CMD &
	PID=$!

	wait $PID
	C_RET=$?
	S_RET=$C_RET
else
	echo "Running: $CMD -s $IP &"
	$CMD -s $IP &
	S_PID=$!

	sleep 1

	echo "Running: $CMD $IP &"
	$CMD $IP &
	C_PID=$!

	wait $C_PID
	C_RET=$?
	wait $S_PID
	S_RET=$?
fi

[[ $C_RET == 61 || $S_RET == 61 ]] && exit 61
[[ $C_RET != 0 || $S_RET != 0 ]] && exit 1
exit 0
