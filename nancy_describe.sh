#!/bin/bash

DEBUG=false
VERBOSE_OUTPUT_REDIRECT=''
ARTIFACTS_PATH=''

#######################################
# Print a help
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function help() {
  echo -e "Describe results of nancy run tests. To start use:
    nancy describe [OPTIONS] artifacts_directory_path
  " | less -RFX
}

#######################################
# Print an error/warning/notice message to STDERR
# Globals:
#   None
# Arguments:
#   (text) Error message
# Returns:
#   None
#######################################
function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $@" >&2
}

#######################################
# Print a debug-level message to STDOUT
# Globals:
#   DEBUG
# Arguments:
#   (text) Message
# Returns:
#   None
#######################################
function dbg() {
  if $DEBUG ; then
    msg "DEBUG: $@"
  fi
}

#######################################
# Print an message to STDOUT
# Globals:
#   None
# Arguments:
#   (text) Message
# Returns:
#   None
#######################################
function msg() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $@"
}

while [ $# -gt 0 ]; do
  case "$1" in
    help )
      help
    exit ;;
    -d | --debug )
      DEBUG=true
      VERBOSE_OUTPUT_REDIRECT=''
      shift ;;
    * )
      option=$1
      option="${option##*( )}"
      option="${option%%*( )}"
      if [[ ! -d $option ]]; then
        err "Artifacts directory not given"
        exit 1
      else
        ARTIFACTS_PATH=$option
        echo "Found $option"
      fi
    break ;;
  esac
done

if [[ -z "$ARTIFACTS_PATH" ]]; then
  err "Artifacts directory not given"
  exit 1
fi

#if [[ -f "$ARTIFACTS_PATH/pgreplay.txt" ]]; then
#  cat "$ARTIFACTS_PATH/pgreplay.txt"
#fi

echo -e "------------------------------------------------------------------------------"
echo -e "Artifacts (collected in \"$ARTIFACTS_PATH/\"):"
echo -e "  Postgres config:    postgresql.conf"
echo -e "  Postgres logs:      postgresql.prepare.log.gz (preparation),"
echo -e "                      postgresql.workload.log.gz (workload)"
echo -e "  pgBadger reports:   pgbadger.html (for humans),"
echo -e "                      pgbadger.json (for robots)"
echo -e "  Stat stapshots:     pg_stat_statements.csv,"
echo -e "                      pg_stat_***.csv"
echo -e "  pgreplay report:    pgreplay.txt"
echo -e "------------------------------------------------------------------------------"
#echo -e "Total execution time: $DURATION"
#echo -e "------------------------------------------------------------------------------"
echo -e "Workload:"
echo -e "  Execution time:     $DURATION_WRKLD"
echo -e "  Total query time:   "$(cat $ARTIFACTS_PATH/pgbadger.json | jq '.overall_stat.queries_duration') " ms"
echo -e "  Queries:            "$(cat $ARTIFACTS_PATH/pgbadger.json | jq '.overall_stat.queries_number')
echo -e "  Query groups:       "$(cat $ARTIFACTS_PATH/pgbadger.json | jq '.normalyzed_info | length')
echo -e "  Errors:             "$(cat $ARTIFACTS_PATH/pgbadger.json | jq '.overall_stat.errors_number')
echo -e "  Errors groups:      "$(cat $ARTIFACTS_PATH/pgbadger.json | jq '.error_info | length')
echo -e "------------------------------------------------------------------------------"

