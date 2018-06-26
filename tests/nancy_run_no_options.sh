#!/bin/bash

output=$(source "${BASH_SOURCE%/*}/../nancy_run.sh" 2>&1)

if [[ $output =~ "ERROR: AWS keys not given" ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  exit 1
fi
