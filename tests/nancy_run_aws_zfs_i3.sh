#!/bin/bash

# Test ZFS on i3

output=$(
  ${BASH_SOURCE%/*}/../nancy run \
    --debug 1 \
    --run-on aws \
    --aws-keypair-name awskey \
    --aws-ssh-key-path /path/.ssh/awskey.pem \
    --aws-ec2-type i3.large \
    --db-dump "create table hello_world as select i from generate_series(1, (10)::int) _(i);" \
    --workload-custom-sql "select 1" \
    --no-pgbadger \
    --aws-zfs \
    2>&1
)

exit_code="$?"

if [[ "$exit_code" -ne "0" ]]; then
  echo -e "\e[31mFAILED\e[39m" >&2
  echo -e "Output: $output" >&2
  exit 1
else
  echo -e "\e[36mOK\e[39m"
fi

