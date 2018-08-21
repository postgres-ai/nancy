#!/bin/bash

read -r -d '' params <<PARAMS
  --run-on aws --aws-keypair-name awskey --pg-version 9.6 \
  --aws-ssh-key-path "/home/someuser/.ssh/awskey.pem" \
  --aws-ec2-type "r4.large" \
  --s3cfg-path "/home/someuser/.s3cfg" \
  --aws-region "us-east-1" \
  --workload-real "s3://somebucket/db.sql.30min.pgreplay" \
  --tmp-path tmp \
  --db-dump "s3://somebucket/dump.sql.bz2" \
  --db-prepared-snapshot "s3://somebucket/snapshot"
PARAMS

output=$(${BASH_SOURCE%/*}/../nancy_run.sh $params 2>&1)

if [[ $output =~ "ERROR: Both snapshot and dump sources are given." ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
fi
