#!/bin/bash

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
parentDir="$(dirname "$thisDir")"
srcDir="$parentDir/.circleci"
if [ ! -d "$srcDir/tmp" ]; then
  mkdir "$srcDir/tmp"
fi
nancyRun="$parentDir/nancy_run.sh"

output=$(
  $nancyRun \
    --db-dump "create table hello_world as select i, i as id from generate_series(1, 1000) _(i);" \
    --workload-real "file://$srcDir/sample.replay" \
    --tmp-path $srcDir/tmp 2>&1
)

regex="Queries:[[:blank:]]*1"
if [[ $output =~ $regex ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
