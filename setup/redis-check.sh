#!/bin/sh

RESULT=`redis-cli ping`

if [ "$RESULT" = "PONG" ]; then
    exit 0
fi

exit 2
