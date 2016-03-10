#!/bin/bash

EXEC=$1
ARGS="$2"
IP=`/sbin/ifconfig |grep ipog -A 1 |grep 'inet addr'| awk '{print $2}' |tr -d 'addr:'`

export PMI_NO_FORK=1
export PMI_NO_PREINITIALIZE=1

echo "Running: $EXEC $ARGS -s $IP &"
$EXEC $ARGS -s $IP &
S_PID=$!

sleep 1

echo "Running: $EXEC $ARGS $IP &"
$EXEC $ARGS $IP &
C_PID=$!

wait $C_PID
C_RET=$?
wait $S_PID
S_RET=$?

[[ $C_RET != 0 || $S_RET != 0 ]] && exit 1

exit 0
