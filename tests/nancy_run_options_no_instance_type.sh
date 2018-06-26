#!/bin/bash

params="--run-on aws --aws-keypair-name awskey --aws-ssh-key-path \"/home/someuser/.ssh/awskey.pem\""
output=$(${BASH_SOURCE%/*}/../nancy_run.sh $params 2>&1)

if [[ $output =~ "ERROR: AWS EC2 Instance type not given." ]]; then
  echo -e "\e[36mOK\e[39m"
  exit 0
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  exit 1
fi
