#!/bin/bash

# Param 1: experiment name, used as artifacts-dirname
# Param 2: instance type
# Param 3: db initialization code 
# Param 4: workload description
# Param 5: yml config file path

CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)

/home/dmius/nancy/nancy_run.sh \
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
  --commands-after-container-init file://$(pwd)/series_data/series_after_init.sh > $(pwd)/series_logs/"$1_$CURRENT_TS".log 2>&1
