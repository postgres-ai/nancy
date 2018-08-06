#!/bin/bash

realpath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

src_dir=$(dirname $(dirname $(realpath "$0")))"/.circleci"

output=$(
  ${BASH_SOURCE%/*}/../nancy run \
    --sql-before-db-restore "select abs from beforeinittable;" \
    --workload-custom-sql "file://$src_dir/custom.sql" \
    --db-dump "file://$src_dir/test.dump.bz2" \
    --tmp-path $src_dir/tmp \
    2>&1
)

if [[ $output =~ "ERROR:  relation \"beforeinittable\" does not exist" ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
