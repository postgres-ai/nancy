#!/bin/bash

## For get results use:
# grep "> latency average" B*.log | awk -F '(i3|i3_|_| +)' '{print $1";"$3";"$4";"$5";"$6";"$7";"$12";"$17}' > B.csv
# grep "excluding connections establishing" A*.log |  awk -F '(i3|i3_|_| +)' '{print $1";"$2"_"$3";"$4";"$5";"$6";"$7";"$12";"$16}' > A.csv


EXPERIMENT_DURATION=1800
#EXPERIMENT_WORKLOAD="-f /storage/workload/read.sql@64 -f /storage/workload/scan.sql@16 -f /storage/workload/write.sql@20 --progress=10"
EXPERIMENT_WORKLOAD="--progress=10"
#WORKLOAD_TYPE="NZ80"
WORKLOAD_TYPE="NZ" # Not zipfian default
FIXED_TPS="-R2000"
EXP_TYPE="DB"

# m4.2xlarge -- 8 CPU 32GB
# m4.4xlarge  -- 16 CPU 64GB

################################################################################
##### FIXED TPS 2000
################################################################################
# AWS_INSTANCE="i3.xlarge" # 4cpu  30.5 GiB 950GiB nvme
AWS_INSTANCE="m4.2xlarge" # 8 cpu  32 GiB
AWS_INSTANCE_NAME="${AWS_INSTANCE/\./_}"
CPU_COUNT=8
DB_SIZE="-s 4000" #60 GiB
DB_SIZE_NAME="60G"
SHB_VALUES="esc23-sb1-39GB-step2.yml"
FIXED_TPS="-R2000"
DRIVE_SIZE="100"
if [[ ! -z "$FIXED_TPS" ]]; then
  EXP_TYPE="B${FIXED_TPS}"
else 
  EXP_TYPE="A"
fi

./nancy_run_experiment.sh "${EXP_TYPE}_${AWS_INSTANCE_NAME}_${DB_SIZE_NAME}_${WORKLOAD_TYPE}_T${EXPERIMENT_DURATION}" "${AWS_INSTANCE}" "${DB_SIZE}" "${EXPERIMENT_WORKLOAD} --no-vacuum -j${CPU_COUNT} -c${CPU_COUNT} --time=${EXPERIMENT_DURATION} -r ${FIXED_TPS}" "$(pwd)/series_data/${SHB_VALUES}" "${DRIVE_SIZE}" &
sleep 3

#AWS_INSTANCE="i3.2xlarge" # 8cpu  61 GiB 1900GiB nvme
AWS_INSTANCE="m4.4xlarge" # 16 cpu  64 GiB
AWS_INSTANCE_NAME="${AWS_INSTANCE/\./_}"
CPU_COUNT=16
DB_SIZE="-s 8000" #120 GiB
DB_SIZE_NAME="120G"
SHB_VALUES="esc46-sb1-62GB-step4.yml"
FIXED_TPS="-R2000"
DRIVE_SIZE="200"
if [[ ! -z "$FIXED_TPS" ]]; then
  EXP_TYPE="B${FIXED_TPS}"
else 
  EXP_TYPE="A"
fi

./nancy_run_experiment.sh "${EXP_TYPE}_${AWS_INSTANCE_NAME}_${DB_SIZE_NAME}_${WORKLOAD_TYPE}_T${EXPERIMENT_DURATION}" "${AWS_INSTANCE}" "${DB_SIZE}" "${EXPERIMENT_WORKLOAD} --no-vacuum -j${CPU_COUNT} -c${CPU_COUNT} --time=${EXPERIMENT_DURATION} -r ${FIXED_TPS}" "$(pwd)/series_data/${SHB_VALUES}" "${DRIVE_SIZE}" & 
sleep 3

################################################################################
##### FIXED TPS 3000
################################################################################
# AWS_INSTANCE="i3.xlarge" # 4cpu  30.5 GiB 950GiB nvme
AWS_INSTANCE="m4.2xlarge" # 8 cpu  32 GiB
AWS_INSTANCE_NAME="${AWS_INSTANCE/\./_}"
CPU_COUNT=8
DB_SIZE="-s 4000" #60 GiB
DB_SIZE_NAME="60G"
SHB_VALUES="esc23-sb1-39GB-step2.yml"
FIXED_TPS="-R3000"
DRIVE_SIZE="100"
if [[ ! -z "$FIXED_TPS" ]]; then
  EXP_TYPE="B${FIXED_TPS}"
else 
  EXP_TYPE="A"
fi

./nancy_run_experiment.sh "${EXP_TYPE}_${AWS_INSTANCE_NAME}_${DB_SIZE_NAME}_${WORKLOAD_TYPE}_T${EXPERIMENT_DURATION}" "${AWS_INSTANCE}" "${DB_SIZE}" "${EXPERIMENT_WORKLOAD} --no-vacuum -j${CPU_COUNT} -c${CPU_COUNT} --time=${EXPERIMENT_DURATION} -r ${FIXED_TPS}" "$(pwd)/series_data/${SHB_VALUES}" "${DRIVE_SIZE}" &
sleep 3

#AWS_INSTANCE="i3.2xlarge" # 8cpu  61 GiB 1900GiB nvme
AWS_INSTANCE="m4.4xlarge" # 16 cpu  64 GiB
AWS_INSTANCE_NAME="${AWS_INSTANCE/\./_}"
CPU_COUNT=16
DB_SIZE="-s 8000" #120 GiB
DB_SIZE_NAME="120G"
SHB_VALUES="esc46-sb1-62GB-step4.yml"
FIXED_TPS="-R3000"
DRIVE_SIZE="200"
if [[ ! -z "$FIXED_TPS" ]]; then
  EXP_TYPE="B${FIXED_TPS}"
else 
  EXP_TYPE="A"
fi

./nancy_run_experiment.sh "${EXP_TYPE}_${AWS_INSTANCE_NAME}_${DB_SIZE_NAME}_${WORKLOAD_TYPE}_T${EXPERIMENT_DURATION}" "${AWS_INSTANCE}" "${DB_SIZE}" "${EXPERIMENT_WORKLOAD} --no-vacuum -j${CPU_COUNT} -c${CPU_COUNT} --time=${EXPERIMENT_DURATION} -r ${FIXED_TPS}" "$(pwd)/series_data/${SHB_VALUES}" "${DRIVE_SIZE}" & 
sleep 3

################################################################################
##### MAX TPS
################################################################################
AWS_INSTANCE="m4.2xlarge" # 8 cpu  32 GiB
AWS_INSTANCE_NAME="${AWS_INSTANCE/\./_}"
CPU_COUNT=8
DB_SIZE="-s 4000" #60 GiB
DB_SIZE_NAME="60G"
SHB_VALUES="esc23-sb1-39GB-step2.yml"
FIXED_TPS=""
DRIVE_SIZE="100"
if [[ ! -z "$FIXED_TPS" ]]; then
  EXP_TYPE="B${FIXED_TPS}"
else 
  EXP_TYPE="A"
fi

./nancy_run_experiment.sh "${EXP_TYPE}_${AWS_INSTANCE_NAME}_${DB_SIZE_NAME}_${WORKLOAD_TYPE}_T${EXPERIMENT_DURATION}" "${AWS_INSTANCE}" "${DB_SIZE}" "${EXPERIMENT_WORKLOAD} --no-vacuum -j${CPU_COUNT} -c${CPU_COUNT} --time=${EXPERIMENT_DURATION} -r ${FIXED_TPS}" "$(pwd)/series_data/${SHB_VALUES}" "${DRIVE_SIZE}" &
sleep 3


AWS_INSTANCE="m4.4xlarge" # 16 cpu  64 GiB
AWS_INSTANCE_NAME="${AWS_INSTANCE/\./_}"
CPU_COUNT=16
DB_SIZE="-s 8000" #120 GiB
DB_SIZE_NAME="120G"
SHB_VALUES="esc46-sb1-62GB-step4.yml"
FIXED_TPS=""
DRIVE_SIZE="200"
if [[ ! -z "$FIXED_TPS" ]]; then
  EXP_TYPE="B${FIXED_TPS}"
else 
  EXP_TYPE="A"
fi

./nancy_run_experiment.sh "${EXP_TYPE}_${AWS_INSTANCE_NAME}_${DB_SIZE_NAME}_${WORKLOAD_TYPE}_T${EXPERIMENT_DURATION}" "${AWS_INSTANCE}" "${DB_SIZE}" "${EXPERIMENT_WORKLOAD} --no-vacuum -j${CPU_COUNT} -c${CPU_COUNT} --time=${EXPERIMENT_DURATION} -r ${FIXED_TPS}" "$(pwd)/series_data/${SHB_VALUES}" "${DRIVE_SIZE}" &
