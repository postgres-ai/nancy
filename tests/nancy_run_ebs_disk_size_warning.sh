#!/bin/bash

output=$(${BASH_SOURCE%/*}/../nancy run \
  --ebs-volume-size sa \
  --workload-custom-sql "file://$srcDir/custom.sql" \
  --db-dump-path "file://$srcDir/test.dump.bz2" \
  --tmp-path $srcDir/tmp \
  2>&1)

if [[ $output =~ "WARNING: ebs-volume-size is not required for aws i3 aws instances and local execution." ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
