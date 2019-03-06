#!/bin/bash

export PATH=$PATH:${BASH_SOURCE%/*}/..

output=$(nancy run --db-dump '--' --db-local-pgdata file:///z --workload-custom-sql '--' 2>&1)

if [[ $output =~ "ERROR: Too many objects (ways to get PGDATA) are specified. Please specify only one." ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
