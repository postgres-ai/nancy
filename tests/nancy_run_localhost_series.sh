#!/bin/bash

realpath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

src_dir=$(dirname $(dirname $(realpath "$0")))"/.circleci"

output=$(
  ${BASH_SOURCE%/*}/../nancy run \
    --less-output \
    --db-pgbench "-s 1" \
    --workload-pgbench "-t 1" \
    --config file://${BASH_SOURCE%/*}/../.circleci/run.yml 2>&1
  )

if [[ $output =~ "Run #1 done." ]] && [[ $output =~ "Run #2 done." ]] && [[ $output =~ "Run #3 done." ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
