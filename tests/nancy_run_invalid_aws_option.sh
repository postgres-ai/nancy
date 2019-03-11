#!/bin/bash

output=$(
  ${BASH_SOURCE%/*}/../nancy run \
    --run-on localhost \
    --aws-keypair-name awskey \
    --aws-ssh-key-path /path/.ssh/awskey.pem \
    --aws-ec2-type i3.large \
    2>&1
)

if [[ $output =~ "may be used only with '--run-on aws'" ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
