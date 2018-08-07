#!/bin/bash

realpath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

src_dir=$(dirname $(dirname $(realpath "$0")))"/.circleci"

# TODO(NikolayS) -aws-ebs-volume-size requires "--run-on aws" – allow these tests in CI

#output=$(
#  ${BASH_SOURCE%/*}/../nancy run \
#    --run-on aws \
#    --aws-ebs-volume-size sa \
#    --workload-custom-sql "file://$src_dir/custom.sql" \
#    --db-dump "file://$src_dir/test.dump.bz2" \
#    --tmp-path $src_dir/tmp \
#   2>&1
#)
#
#if [[ $output =~ "ERROR: ebs-volume-size must be integer." ]]; then
#  echo -e "\e[36mOK\e[39m"
#else
#  >&2 echo -e "\e[31mFAILED\e[39m"
#  >&2 echo -e "Output: $output"
#  exit 1
#fi
