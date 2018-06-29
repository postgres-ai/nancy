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
    --db-dump-path "file://$srcDir/test.dump.bz2" \
    --tmp-path $srcDir/tmp
)

if [[ $output =~ "Queries duration:" ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  exit 1
fi
