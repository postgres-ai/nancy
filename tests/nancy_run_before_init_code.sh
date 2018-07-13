#!/bin/bash

output=$(${BASH_SOURCE%/*}/../nancy run \
  --before-db-init-code "select abs from beforeinittable;" \
  --workload-custom-sql "file://$srcDir/custom.sql" \
  --db-dump-path "file://$srcDir/test.dump.bz2" \
  --tmp-path $srcDir/tmp \
  2>&1)

if [[ $output =~ "ERROR:  relation \"beforeinittable\" does not exist" ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
