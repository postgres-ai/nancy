#!/bin/bash

source ${BASH_SOURCE%/*}/../parse_yaml.sh "${BASH_SOURCE%/*}/../../.circleci/run.yml" "yml_"

i=0
while : ; do
  var_name_config="yml_run_"$i"_delta_config"
  delta_config=$(eval echo \$$var_name_config)
  delta_config=$(echo $delta_config | tr ";" "\n")
  var_name_ddl_do="yml_run_"$i"_delta_ddl_do"
  delta_ddl_do=$(eval echo \$$var_name_ddl_do)
  var_name_ddl_undo="yml_run_"$i"_delta_ddl_undo"
  delta_ddl_undo=$(eval echo \$$var_name_ddl_undo)
  [[ -z $delta_config ]] && [[ -z $delta_ddl_do ]] && [[ -z $delta_ddl_undo ]] && break;
  let j=$i*3
  RUNS[$j]="$delta_config"
  [[ -z $delta_config ]] && RUNS[$j]=""
  RUNS[$j+1]="$delta_ddl_do"
  [[ -z $delta_ddl_do ]] && RUNS[$j+1]=""
  RUNS[$j+2]="$delta_ddl_undo"
  [[ -z $delta_ddl_undo ]] && RUNS[$j+2]=""
  let i=i+1
done
# validate runs config
runs_count=${#RUNS[*]}
let runs_count=runs_count/3

if [[ "$runs_count" -eq "3" ]] ; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  echo "YML runs config count: $runs_count"
  exit 1
fi
