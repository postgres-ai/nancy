#!/bin/bash

output=$(source "${BASH_SOURCE%/*}/../nancy_run.sh" 2>&1)

if [[ $output =~ "ERROR: AWS keys not given" ]]; then
  echo "OK!"
else
  >&2 echo "FAILED"
fi


#
#if [[ $(./nancy_run.sh --aws-key-path ~/.ssh/awskey.pem --aws-key-pair awskey  --pg-version 9.6 --artifacts-destination s3://postgres-misc/tmp --workload-custom-sql 'select pg_sleep(1);' --db-dump-path s3://postgres-misc/db.dumps/postila_ru.dump.sql.bz2 --clean-run-only YEEES --target-ddl-do 'select 1;' 2>&1  | grep "ERROR: 2 or more targets given." | wc -l) == 1 ]]; then
#  echo "OK!";
#else
#  >&2 echo "FAILED";
#fi
