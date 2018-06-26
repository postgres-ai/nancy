#!/bin/bash

#set -ueox pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
parentDir="$(dirname "$thisDir")"
srcDir="$parentDir/.circleci"
#bzip2 "$srcDir/test.dump"
if [ ! -d "$srcDir/tmp" ]; then
  mkdir "$srcDir/tmp"
fi
nancyRun="$parentDir/nancy_run.sh"

$nancyRun --workload-custom-sql $srcDir/custom.sql --db-dump-path $srcDir/test.dump.bz2 --tmp-path $srcDir/tmp >&2 \
  || (echo -e "\e[31mFAILED\e[39m" && exit 1)

echo -e "\e[36mOK\e[39m"
