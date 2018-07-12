#!/bin/bash

DEBUG=0

## Get command line params
while true; do
  case "$1" in
    help )
        echo -e "\033[1mCOMMAND\033[22m

    run

\033[1mDESCRIPTION\033[22m

  Nancy is a member of Postgres.ai's Artificial DBA team responsible for
  conducting experiments.

  Use 'nancy prepare-workload' to prepare real-world workload based on Postgres
  logs from any of your real Postgres server.

  WIP! Not finished. More details TBD later.

\033[1mSEE ALSO\033[22m
    " | less -RFX
        exit ;;
    -d | --debug ) DEBUG=1; shift ;;
    --db-name )
      DB_NAME="$2"; shift 2 ;;
    -- )
      >&2 echo "ERROR: Invalid option '$1'"
      exit 1
      break ;;
    * )
      if [ "${1:0:2}" == "--" ]; then
        >&2 echo "ERROR: Invalid option '$1'. Please double-check options."
        exit 1
      else
        INPUT="$1"
      fi
      break ;;
  esac
done

if [ $DEBUG -eq 1 ]; then
  echo "debug: ${DEBUG}"
  echo "input: ${INPUT}"
  echo "output: ${OUTPUT}"
  echo "db_name: ${DB_NAME}"
fi
