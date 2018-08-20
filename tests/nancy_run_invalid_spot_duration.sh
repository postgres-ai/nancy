#!/bin/bash

output=$(
  ${BASH_SOURCE%/*}/../nancy run \
    --run-on aws \
    --aws-keypair-name awskey \
    --aws-ssh-key-path /path/.ssh/awskey.pem \
    --aws-ec2-type i3.large \
    --aws-block-duration 30 \
    2>&1
)

if [[ $output =~ " Container live time duration (--aws-block-duration) has wrong value: 30. Available values of AWS spot instance duration in minutes is 60, 120, 180, 240, 300, or 360)." ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
