#!/bin/bash

output=$( \
  ${BASH_SOURCE%/*}/../nancy prepare-workload --db-name testci \
    --output ./test.replay ./.circleci/sample.log \
    2>&1
)
if [[ $output =~ "Total SQL statements processed: 2" ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi

