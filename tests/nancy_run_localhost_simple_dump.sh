#!/bin/bash
test_passed=true

realpath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

src_dir=$(dirname $(dirname $(realpath "$0")))"/.circleci"

output=$(
  ${BASH_SOURCE%/*}/../nancy run \
    --workload-custom-sql "file://$src_dir/custom.sql" \
    --db-dump "file://$src_dir/test.dump.bz2" \
    --tmp-path $src_dir/tmp 2>&1
)

regex="Errors:[[:blank:]]*0"
if [[ ! $output =~ $regex ]]; then
  test_passed=false
fi

artifacts_location=$(
  echo "$output" | grep "Artifacts (collected in " | awk -F"\"" '{print $2}'
)
if [[ ! $(grep Linux "$artifacts_location/system_info.txt") =~ ^Linux ]]; then
  test_passed=false
fi

if [[ $test_passed ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
