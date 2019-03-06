#!/bin/bash

params="--run-on aws --aws-keypair-name awskey --aws-ssh-key-path \"/home/someuser/.ssh/awskey.pem\""
output=$(${BASH_SOURCE%/*}/../nancy_run.sh $params 2>&1)

if [[ $output =~ "ERROR: AWS EC2 Instance type is not specified." ]]; then
  echo -e "\e[36mOK\e[39m"
  exit 0
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
  exit 1
fi
