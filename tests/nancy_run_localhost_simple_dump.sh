#!/bin/bash

echo "SKIP" && exit 0

set -ueo pipefail
#for debugging

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
parentDir="$(dirname "$thisDir")"
srcDir="$parentDir/.circleci"
#bzip2 "$srcDir/test.dump"
if [ ! -d "$srcDir/tmp" ]; then
  mkdir "$srcDir/tmp"
fi
nancyRun="$parentDir/nancy_run.sh"

output=$(
  $nancyRun --workload-custom-sql $srcDir/custom.sql --db-dump-path $srcDir/test.dump.bz2 \
    --tmp-path $srcDir/tmp --debug 2>&1
)

if [[ $output =~ "Queries duration:" ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  exit 1
fi
