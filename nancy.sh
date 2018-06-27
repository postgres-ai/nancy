#!/bin/bash

cmd=""

case "$1" in
    run )  
        cmd="./nancy_run.sh"
        shift
        ;;
    workload ) 
        cmd="./nancy_workload.sh"
        shift
        ;;
    help )
        echo "Here will be help! Comming soon."
        exit 1;
        ;;
    * ) 
        >&2 echo "ERROR: Unknown command."
        exit 1;
    ;;
esac

while [ -n "$1" ]
do
    cmd="$cmd $1"
    shift
done

#echo "CMD: $cmd"
${cmd}

