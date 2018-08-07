#!/bin/bash

realpath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

src_dir=$(dirname $(dirname $(realpath "$0")))"/.circleci"

output=$(
  ${BASH_SOURCE%/*}/../nancy run \
    --db-dump "create table hello_world as select i, i as id from generate_series(1, 1000) _(i);" \
    --workload-real "file://$src_dir/sample.replay" \
    --tmp-path $src_dir/tmp 2>&1
)

regex="Queries:[[:blank:]]*1"
if [[ $output =~ $regex ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
