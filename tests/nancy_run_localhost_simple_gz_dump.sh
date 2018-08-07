#!/bin/bash

realpath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

src_dir=$(dirname $(dirname $(realpath "$0")))"/.circleci"
if [ ! -d "$src_dir/tmp" ]; then
  mkdir "$src_dir/tmp"
fi

output=$(
  ${BASH_SOURCE%/*}/../nancy run \
    --workload-custom-sql "file://$src_dir/custom.sql" \
    --db-dump "file://$src_dir/test.dump.gz" \
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
