#!/bin/bash

output=$(${BASH_SOURCE%/*}/../nancy_run.sh --run-on aws 2>&1)

if [[ $output =~ "AWS keypair name and ssh key file must be specified" ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
