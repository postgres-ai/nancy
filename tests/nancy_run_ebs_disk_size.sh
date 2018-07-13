#!/bin/bash

output=$(${BASH_SOURCE%/*}/../nancy run \
  --debug \
  --ebs-volume-size 37 \
  2>&1)

if [[ $output =~ "ebs-volume-size: 37" ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
