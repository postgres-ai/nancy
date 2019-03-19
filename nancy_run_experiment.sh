#!/bin/bash

# Param 1: experiment name, used as artifacts-dirname
# Param 2: instance type
# Param 3: db initialization code 
# Param 4: workload description
# Param 5: yml config file path
# Param 5: drive size

CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)

mkdir -p ./series_results
mkdir -p ./series_tmp
mkdir -p ./series_logs

$(pwd)/nancy_run.sh \
  --debug \
  --run-on aws \
  --aws-keypair-name awskey3 \
  --aws-ssh-key-path file:///home/dmius/.ssh/awskey3.pem \
  --aws-ec2-type "$2" \
  --pg-version 11 \
  --pg-config file://$(pwd)/series_data/pg.conf \
  --tmp-path $(pwd)/series_tmp \
  --artifacts-destination $(pwd)/series_results \
  --config "file://$5" \
  --db-pgbench "$3" \
  --workload-pgbench "$4" \
  --artifacts-dirname "$1_$CURRENT_TS" \
  --sql-after-db-restore file://$(pwd)/series_data/after_db_restore.sql \
  --no-pgbadger \
  --aws-zfs \
  --aws-ebs-volume-size "$6" \
  --commands-after-container-init file://$(pwd)/series_data/series_after_init.sh > $(pwd)/series_logs/"$1_$CURRENT_TS".log 2>&1

#  --debug \
#  --keep-alive 3600 \

