#!/bin/bash

export PATH=$PATH:${BASH_SOURCE%/*}/..

output=$(nancy run --run-on aws 2>&1)

if [[ $output =~ "ERROR: AWS keys not given" ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  exit 1
fi
