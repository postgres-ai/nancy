#!/bin/bash

MACHINE_HOME="/machine_home"

echo "time;MemFree,kB;Buffers,kB;Active(file),kB;Inactive(file),kB;SwapFree,kB;Shmem,kB;Slab,kB;PageTables,kB" > $MACHINE_HOME/meminfo.run.csv
while true; do
  dt=$(date --rfc-3339=ns)
  echo "${dt}" >> $MACHINE_HOME/meminfo.run.log
  cat /proc/meminfo > $MACHINE_HOME/meminfo.log
  cat $MACHINE_HOME/meminfo.log >> $MACHINE_HOME/meminfo.run.log
  echo "" >> $MACHINE_HOME/meminfo.run.log
  meminfo="${dt}"
  for param in "MemFree" "Buffers" "Active\(file\)" "Inactive\(file\)" "SwapFree" "Shmem" "Slab" "PageTables"
  do
    paramValue=$(bash -c "cat ${MACHINE_HOME}/meminfo.log | grep -P '^${param}: +.+ .+' | awk '{print \$2}'")
    meminfo="${meminfo};${paramValue}"
  done
  echo -e "${meminfo}" >> $MACHINE_HOME/meminfo.run.csv
  sleep $FREQ
done;