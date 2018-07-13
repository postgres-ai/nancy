#!/bin/bash

# CAUTION: these checks will definitely not work on non-Debian(Ubuntu) machines,
# In general, all this script is very fragile. TODO improve

failures=0

output=$( \
  nancy prepare-workload --db-name testci \
    --output ./test.replay ./.circleci/sample.log \
    2>&1
)
if [ "${output:0:27}" != "ERROR: GNU awk is required." ]; then
  failures=$((failures+1))
fi

sudo apt-get install gawk # only Ubuntu/Debian! TODO

output=$( \
  nancy prepare-workload --db-name testci \
    --output ./test.replay ./.circleci/sample.log \
    2>&1
)
if [ "${output:0:33}" != "ERROR: pgreplay is not installed." ]; then
  failures=$((failures+1))
  echo "out: $output"
fi

sudo apt-get install pgreplay # only Ubuntu/Debian! TODO

output=$( \
  nancy prepare-workload --db-name testci \
    --output ./test.replay ./.circleci/sample.log \
    2>&1
)
if [[ $output =~ "Total SQL statements processed: 2" ]]; then
  :
else
  failures=$((failures+1))
fi

if [ "$failures" -eq "0" ]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "$failures/3 of checks failed"
  exit 1
fi

