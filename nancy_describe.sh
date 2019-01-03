#!/bin/bash
#
# 2018–2019 © Postgres.ai
#
# Describe one or more experimental runs, taking
# collection(s) of artifacts as input.

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
    nancy describe %artifacts_directory_path%
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

#######################################
# Print an 5 top slowest queries
# Globals:
#   ARTIFACTS_PATH
# Arguments:
#   (int) count of slowest queries
# Returns:
#   None
#######################################
function out_top_slowest() {
  local top_count=$1
  local i=0
  local j=1
  while : ; do
    let j=$i+1
    echo -e "  Slowest query #$j."
    duration=$(cat $FILE_PATH | jq '.top_slowest | .['$i'] | .[0]')
    duration="${duration/\"/}"
    duration="${duration/\"/}"
    query=$(cat $FILE_PATH | jq '.top_slowest | .['$i'] | .[2]')
    query="${query//'\\n'/}"
    query="${query//'\\\"'/'"'}" #'
    echo -e "    Duration is: $duration ms"
    echo -e "    Query text: $query\n"
    let i=$i+1
    [[ "$i" -eq "$top_count" ]] && break;
  done
}

#######################################
# Print an durations of slowest queries in different runs
# Globals:
#   ARTIFACTS_PATH
# Arguments:
#   (int) count of slowest queries to analyze
# Returns:
#   (int) 1 if is not series experiment
#######################################
function compare_series_slowest() {
  local top_count=$1
  # Check is series experiment
  if [[ ! -f "$ARTIFACTS_PATH/pgbadger.1.json" ]]; then
    msg "Experiment is not series."
    return 1
  fi
  local file_path=$ARTIFACTS_PATH/pgbadger.1.json
  local i=0
  local j=1
  while : ; do
    let j=$i+1
    echo -e "  Slowest query #$j."
    duration=$(cat $file_path | jq '.top_slowest | .['$i'] | .[0]')
    duration="${duration/\"/}"
    duration="${duration/\"/}"
    query=$(cat $file_path | jq '.top_slowest | .['$i'] | .[2]')
    query_text="${query//'\\n'/}"
    query_text="${query_text//'\\\"'/'"'}" #'
    echo -e "    Slowest query text: $query_text"
    echo -e "    Run 1 duration is:\t$duration ms"
    local fi=2
    while : ; do
      if [[ ! -f "$ARTIFACTS_PATH/pgbadger.$fi.json" ]]; then
        dbg "File $ARTIFACTS_PATH/pgbadger.$fi.json not found"
        break
      fi
      local qi=0
      local fcount=$(cat $ARTIFACTS_PATH/pgbadger.$fi.json | jq '.top_slowest | length')
      while : ; do
        qduration=$(cat $ARTIFACTS_PATH/pgbadger.$fi.json | jq '.top_slowest | .['$qi'] | .[0]')
        qduration="${qduration/\"/}"
        qduration="${qduration/\"/}"
        qquery=$(cat $ARTIFACTS_PATH/pgbadger.$fi.json | jq '.top_slowest | .['$qi'] | .[2]')
        if [[ "$query" == "$qquery" ]]; then
          echo -e "    Run $fi duration is:\t$qduration ms"
        fi
        let qi=$qi+1
        [[ "$qi" -eq "$fcount" ]] && break;
      done
      let fi=$fi+1
    done
    let i=$i+1
    [[ "$i" -eq "$top_count" ]] && break;
  done
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

if [[ -f "$ARTIFACTS_PATH/pgbadger.json" ]]; then
  FILE_PATH=$ARTIFACTS_PATH/pgbadger.json
  echo -e "------------------------------------------------------------------------------"
  echo -e "Artifacts (collected in \"$ARTIFACTS_PATH\"):"
  echo -e "  Postgres config:    postgresql.conf"
  echo -e "  Postgres logs:      postgresql.prepare.log.gz (preparation),"
  echo -e "                      postgresql.workload.log.gz (workload)"
  echo -e "  pgBadger reports:   pgbadger.html (for humans),"
  echo -e "                      pgbadger.json (for robots)"
  echo -e "  Stat stapshots:     pg_stat_statements.csv,"
  echo -e "                      pg_stat_***.csv"
  echo -e "  pgreplay report:    pgreplay.txt"
  echo -e "------------------------------------------------------------------------------"
  echo -e "Workload:"
  echo -e "  Total query time:   "$(cat $FILE_PATH | jq '.overall_stat.queries_duration') " ms"
  echo -e "  Queries:            "$(cat $FILE_PATH | jq '.overall_stat.queries_number')
  echo -e "  Query groups:       "$(cat $FILE_PATH | jq '.normalyzed_info | length')
  echo -e "  Errors:             "$(cat $FILE_PATH | jq '.overall_stat.errors_number')
  echo -e "  Errors groups:      "$(cat $FILE_PATH | jq '.error_info | length')
  echo -e "------------------------------------------------------------------------------"
elif [[ -f "$ARTIFACTS_PATH/pgbadger.1.json" ]]; then
  FILE_PATH=$ARTIFACTS_PATH/pgbadger.1.json
  SERIES_COUNT=2
  while : ; do
    if [[ ! -f "$ARTIFACTS_PATH/pgbadger.$SERIES_COUNT.json" ]]; then
      let SERIES_COUNT=$SERIES_COUNT-1
      break
    fi
    let SERIES_COUNT=$SERIES_COUNT+1
  done
  echo -e "------------------------------------------------------------------------------"
  echo -e "Runs count:           $SERIES_COUNT"
  echo -e "Experiment artifacts collected in \"$ARTIFACTS_PATH/\"."
  echo -e "Postgres prepare log: postgresql.prepare.log.gz (preparation),"
  echo -e "------------------------------------------------------------------------------"
  local i=1;
  while : ; do
    FILE_PATH="$ARTIFACTS_PATH/pgbadger.$i.json"
    echo -e "\n"
    echo -e "Run $i"
    echo -e "------------------------------------------------------------------------------"
    echo -e "Run artifacts (collected in \"$ARTIFACTS_PATH\"):"
    echo -e "  Postgres config:    postgresql.$i.conf"
    echo -e "  Postgres log:       postgresql.workload.$i.log.gz (workload)"
    echo -e "  pgBadger reports:   pgbadger.$i.html (for humans),"
    echo -e "                      pgbadger.$i.json (for robots)"
    echo -e "  Stat stapshots:     pg_stat_statements.$i.csv,"
    echo -e "                      pg_stat_***.$i.csv"
    echo -e "  pgreplay report:    pgreplay.$i.txt"
    echo -e "------------------------------------------------------------------------------"
    echo -e "Workload:"
    echo -e "  Total query time:   "$(cat $FILE_PATH | jq '.overall_stat.queries_duration') " ms"
    echo -e "  Queries:            "$(cat $FILE_PATH | jq '.overall_stat.queries_number')
    echo -e "  Query groups:       "$(cat $FILE_PATH | jq '.normalyzed_info | length')
    echo -e "  Errors:             "$(cat $FILE_PATH | jq '.overall_stat.errors_number')
    echo -e "  Errors groups:      "$(cat $FILE_PATH | jq '.error_info | length')
    echo -e "------------------------------------------------------------------------------"
    let i=$i+1
    [[ "$i" -eq "$SERIES_COUNT" ]] && break;
  done
fi
compare_series_slowest 5
if [ $? -ne 0 ]; then
  out_top_slowest 5
fi
