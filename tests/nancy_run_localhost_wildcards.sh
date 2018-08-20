#!/bin/bash

realpath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

src_dir=$(dirname $(dirname $(realpath "$0")))"/.circleci"

output=$(
  ${BASH_SOURCE%/*}/../nancy run \
    --db-dump "create table t1 as select * from generate_series(1, 1000);" \
    --workload-custom-sql "select count(*) from t1;" \
    --tmp-path $src_dir/tmp 2>&1
)

regex="Errors:[[:blank:]]*0"
if [[ $output =~ $regex ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi

