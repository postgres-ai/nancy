#!/bin/bash

START_VALUE=100
STEP=100
MAX_VALUE=20000
PER_FILE=20
PARAM_NAME="shared_buffers"
PARAM_UNIT="MB"
FILE_NAME="shared_buffers_config"
declare -a CONFIGS

fileNum=1
configNum=0
filePos=0
# Generate configs 
for value in $(seq $START_VALUE $STEP $MAX_VALUE); do
  if [[ $filePos == 0  ]]; then
    fileName="shared_buffers_config_$fileNum.yml"
    CONFIGS[$configNum]=$fileName
    let configNum=configNum+1
    let fileNum=fileNum+1
    echo "run:" > $fileName
  fi;
  echo "  $filePos:" >> $fileName
  echo "    delta_config: $PARAM_NAME = $value$PARAM_UNIT" >> $fileName
  let filePos=filePos+1
  if [[ $filePos == $PER_FILE ]]; then
    filePos=0
  fi
done

# Start experiment for every config with timeout
configs_count=${#CONFIGS[*]}
j=0
n=1
while : ; do
  let n=j+1
  config=${CONFIGS[$j]}
  echo "Start experiment for $config"
  nohup bash ./nancy_run_series.sh "./$config" > "series_${n}_results.log" 2>&1 &
  sleep 3  
  let j=j+1
  if [[ $j == $configs_count ]]; then
    break
  fi
done