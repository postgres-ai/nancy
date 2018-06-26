#!/bin/bash

params="--run-on aws --aws-keypair-name awskey --aws-ssh-key-path \"/home/someuser/.ssh/awskey.pem\""
output=$(source "${BASH_SOURCE%/*}/../nancy_run.sh" $params 2>&1)

if [[ $output =~ "ERROR: Instance type not given." ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  exit 1
fi
