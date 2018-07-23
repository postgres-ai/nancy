#!/bin/bash

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
parentDir="$(dirname "$thisDir")"
srcDir="$parentDir/.circleci"
if [ ! -d "$srcDir/tmp" ]; then
  mkdir "$srcDir/tmp"
fi
nancyRun="$parentDir/nancy_run.sh"

output=$(
  $nancyRun --workload-custom-sql "file://$srcDir/custom.sql" \
    --db-dump "file://$srcDir/test.dump.gz" \
    --tmp-path $srcDir/tmp 2>&1
)

if [[ $output =~ "Errors:            0:" ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
