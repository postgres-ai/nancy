#!/bin/bash
#
# 2018 © Nikolay Samokhvalov nikolay@samokhvalov.com
# 2018 © Postgres.ai
#
# Perform a single run of a database experiment
# Usage: use 'nancy run help' or see the corresponding code below.

# Globals (some of them can be modified below)
KB=1024
DEBUG=0
CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
DOCKER_MACHINE="nancy-$CURRENT_TS"
DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
KEEP_ALIVE=0
VERBOSE_OUTPUT_REDIRECT=" > /dev/null"
EBS_SIZE_MULTIPLIER=15
POSTGRES_VERSION_DEFAULT=10

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
  [[ "$DEBUG" -eq "1" ]] && msg "DEBUG: $@"
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

# Process CLI parameters
while true; do
  case "$1" in
    help )
      echo -e "\033[1mCOMMAND\033[22m

  run

\033[1mDESCRIPTION\033[22m

  Use 'nancy run' to perform a single run for a database experiment.

  A DB experiment consists of one or more 'runs'. For example, if Nancy is being
  used to verify  that a new index  will affect  performance only in a positive
  way, two runs are needed. If one needs to only  collect query plans for each
  query group, a single run is enough. And finally, if there is  a goal to find
  an optimal value for some PostgreSQL setting, multiple runs will be needed to
  check how various values of the specified setting affect performance of the
  specified database and workload.

  An experimental run needs the following 4 items to be provided as an input:
    - environment: hardware or cloud instance type, PostgreSQL version, etc;
    - database: copy or clone of the database;
    - workload: 'real' workload or custom SQL;
    - (optional) delta (a.k.a. target): some DB change to be evaluated:
      * PostgreSQL config changes, or
      * some DDL (or arbitrary SQL) such as 'CREATE INDEX ...', or
      * theoretically, anything else.

\033[1mOPTIONS\033[22m

  NOTICE: A value for a string option that starts with 'file://' is treated as
          a path to a local file. A string value starting with 's3://' is
          treated as a path to remote file located in S3 (AWS S3 or analog).
          Otherwise, a string values is considered as 'content', not a link to
          a file.

  \033[1m--debug\033[22m (boolean)

  Turn on debug logging. This significantly increases the level of verbosity
  of messages being sent to STDOUT.

  \033[1m--keep-alive\033[22m (integer)

  How many seconds the entity (Docker container, Docker machine) will remain
  alive after the main activity of the run is finished. Useful for
  debugging (using ssh access to the container), for serialization of
  multiple experimental runs, for optimization of resource (re-)usage.

  WARNING: in clouds, use it with care to avoid unexpected expenses.

  \033[1m--run-on\033[22m (string)

  Where the experimental run will be performed. Allowed values:

    * 'localhost' (default)

    * 'aws'

    * 'gcp' (WIP, not yet implemented)

  If 'localhost' is specified (or --run-on is omitted), Nancy will perform the
  run on the localhost in a Docker container so ('docker run' must work
  locally).

  If 'aws' is specified, Nancy will use a Docker machine (EC2 Spot Instance)
  with a single container on it.

  \033[1m--tmp-path\033[22m (string)

  Path to the temporary directory on the current machine (where 'nancy run' is
  being invoked), to store various files while preparing them to be shipped to
  the experimental container/machine. Default: '/tmp'.

  \033[1m--container-id\033[22m (string)

  If specified, new container/machine will not be created. Instead, the existing
  one will be reused. This might be a significant optimization for a series of
  experimental runs to be executed sequentially.

  WARNING: This option is to be used only with read-only workloads.

  WIP: Currently, this option works only with '--run-on localhost'.

  \033[1m--pg-version\033[22m (string)

  Specify the major version of PostgreSQL. Allowed values:

    * '9.6'
    * '10' (default)

  Currently, there is no way to specify the minor version – it is always the
  most recent version, available in the official PostgreSQL APT repository (see
  https://www.postgresql.org/download/linux/ubuntu/).

  \033[1m--pg-config\033[22m (string)

  PostgreSQL config to be used (may be partial).

  \033[1m--db-prepared-snapshot\033[22m (string)

  Reserved / Not yet implemented.

  \033[1m--db-dump\033[22m (string)

  Database dump (created by pg_dump) to be used as an input. May be:

    * path to dump file (must start with 'file://' or 's3://'), may be:
      - plain dump made with 'pg_dump',
      - gzip-compressed plain dump ('*.gz'),
      - bzip2-compressed plain dump ('*.bz2'),
      - dump in \"custom\" format, made with 'pg_dump -Fc ..' ('*.pgdmp'),
    * sequence of SQL commands specified as in a form of plain text.

  \033[1m--commands-after-container-init\033[22m (string)

  Shell commands to be executed after the container initialization. Can be used
  to add additional software such as Postgres extensions not present in
  the main contrib package.

  \033[1m--sql-before-db-restore\033[22m (string)

  Additional SQL queries to be executed before the database is initiated.
  Applicable only when '--db-dump' is used.

  \033[1m--sql-after-db-restore\033[22m (string)

  Additional SQL queries to be executed once the experimental database is
  initiated and ready to accept connections.

  \033[1m--workload-real\033[22m (string)

  'Real' workload – path to the file prepared by using 'nancy prepare-workload'.

  \033[1m--workload-real-replay-speed\033[22m (integer)

  The speed of replaying of the 'real workload'. Useful for stress-testing
  and forecasting the performance of the database under heavier workloads.

  \033[1m--workload-custom-sql\033[22m (string)

  SQL queries to be used as workload. These queries will be executed in a signle
  database session.

  \033[1m--workload-basis\033[22m (string)

  Reserved / Not yet implemented.

  \033[1m--delta-sql-do\033[22m (string)

  SQL changing database somehow before running workload. For example, DDL:

    create index i_t1_experiment on t1 using btree(col1);

  \033[1m--delta-sql-undo\033[22m (string)

  SQL reverting changes produced by those specified in the value of the
  '--delta-sql-do' option. Reverting allows to serialize multiple runs, but it
  might be not possible in some cases. 'UNDO SQL' example reverting index
  creation:

    drop index i_t1_experiment;

  \033[1m--delta-config\033[22m (string)

  Config changes to be applied to postgresql.conf before running workload.
  Once configuration changes are made, PostgreSQL is restarted. Example:

    random_page_cost = 1.1

  \033[1m--artifacts-destination\033[22m (string)

  Path to a local ('file://...') or S3 ('s3://...') directory where artifacts
  of the experimental run will be placed. Among these artifacts:

    * detailed performance report in JSON format
    * whole PostgreSQL log, gzipped
    * full PostgreSQL config used in this experimental run

  \033[1m--aws-ec2-type\033[22m (string)

  Type of EC2 instance to be used. To keep budgets low, EC2 Spot instances will
  be utilized and automatic detections of the lowest price in the current AZ
  will be performed.

  WARNING: 'i3-metal' instances are not currently supported (WIP).

  The option may be used only with '--run-on aws'.

  \033[1m--aws-keypair-name\033[22m (string)

  The name of key pair to be used on EC2 instance to allow ssh access. Must
  correspond to SSH key file specified in the '--aws-ssh-key-path' option.

  The option may be used only with '--run-on aws'.

  \033[1m--aws-ssh-key-path\033[22m (string)

  Path to SSH key file (usually, has '.pem' extension).

  The option may be used only with '--run-on aws'.

  \033[1m--aws-ebs-volume-size\033[22m (string)

  Size (in gigabytes) of EBS volume to be attached to the EC2 instance.

  \033[1m--s3cfg-path\033[22m

  The path the '.s3cfg' configuration file to be used when accessing files in
  S3. This file must be local and must be specified if some options' values are
  in 's3://***' format.

  See also: https://github.com/s3tools/s3cmd

\033[1mSEE ALSO\033[22m

  nancy help

    " | less -RFX
    exit ;;
    -d | --debug )
      DEBUG=1;
      VERBOSE_OUTPUT_REDIRECT='';
      shift ;;
    --keep-alive )
      KEEP_ALIVE="$2"; shift 2 ;;
    --run-on )
      RUN_ON="$2"; shift 2 ;;
    --tmp-path )
      TMP_PATH="$2"; shift 2 ;;
    --container-id )
      CONTAINER_ID="$2"; shift 2 ;;
    --pg-version )
      PG_VERSION="$2"; shift 2 ;;
    --pg-config )
      PG_CONFIG="$2"; shift 2;;
    --db-prepared-snapshot )
      #Still unsupported
      DB_PREPARED_SNAPSHOT="$2"; shift 2 ;;
    --db-dump )
      DB_DUMP="$2"; shift 2 ;;
    --commands-after-container-init )
      COMMANDS_AFTER_CONTAINER_INIT="$2"; shift 2 ;;
    --sql-before-db-restore )
      #s3 url|filename|content
      SQL_BEFORE_DB_RESTORE="$2"; shift 2 ;;
    --sql-after-db-restore )
      #s3 url|filename|content
      SQL_AFTER_DB_RESTORE="$2"; shift 2 ;;
    --workload-custom-sql )
      #s3 url|filename|content
      WORKLOAD_CUSTOM_SQL="$2"; shift 2 ;;
    --workload-real )
      #s3 url
      WORKLOAD_REAL="$2"; shift 2 ;;
    --workload-real-replay-speed )
      WORKLOAD_REAL_REPLAY_SPEED="$2"; shift 2 ;;
    --workload-basis )
      #Still unsupported
      WORKLOAD_BASIS="$2"; shift 2 ;;
    --delta-sql-do )
      #s3 url|filename|content
      DELTA_SQL_DO="$2"; shift 2 ;;
    --delta-sql-undo )
      #s3 url|filename|content
      DELTA_SQL_UNDO="$2"; shift 2 ;;
    --delta-config )
      #s3 url|filename|content
      DELTA_CONFIG="$2"; shift 2 ;;
    --artifacts-destination )
      ARTIFACTS_DESTINATION="$2"; shift 2 ;;
    --artifacts-filename )
      ARTIFACTS_FILENAME="$2"; shift 2 ;;

    --aws-ec2-type )
      AWS_EC2_TYPE="$2"; shift 2 ;;
    --aws-keypair-name )
      AWS_KEYPAIR_NAME="$2"; shift 2 ;;
    --aws-ssh-key-path )
      AWS_SSH_KEY_PATH="$2"; shift 2 ;;
    --aws-ebs-volume-size )
        AWS_EBS_VOLUME_SIZE="$2"; shift 2 ;;

    --s3cfg-path )
      S3_CFG_PATH="$2"; shift 2 ;;
    * )
      option=$1
      option="${option##*( )}"
      option="${option%%*( )}"
      if [[ "${option:0:2}" == "--" ]]; then
        err "ERROR: Invalid option '$1'. Please double-check options."
        exit 1
      elif [[ "$option" != "" ]]; then
        err "ERROR: \"nancy run\" does not support payload (except \"help\"). Use options, see \"nancy run help\")"
        exit 1
      fi
    break ;;
  esac
done

RUN_ON=${RUN_ON:-localhost}

if [[ $DEBUG -eq 1 ]]; then
  echo "DEBUG: ${DEBUG}"
  echo "KEEP_ALIVE: ${KEEP_ALIVE}"
  echo "RUN_ON: ${RUN_ON}"
  echo "CONTAINER_ID: ${CONTAINER_ID}"
  echo "AWS_EC2_TYPE: ${AWS_EC2_TYPE}"
  echo "AWS_KEYPAIR_NAME: $AWS_KEYPAIR_NAME"
  echo "AWS_SSH_KEY_PATH: $AWS_SSH_KEY_PATH"
  echo "PG_VERSION: ${PG_VERSION}"
  echo "PG_CONFIG: ${PG_CONFIG}"
  echo "DB_PREPARED_SNAPSHOT: ${DB_PREPARED_SNAPSHOT}"
  echo "DB_DUMP: $DB_DUMP"
  echo "COMMANDS_AFTER_CONTAINER_INIT: $COMMANDS_AFTER_CONTAINER_INIT"
  echo "SQL_BEFORE_DB_RESTORE: $SQL_BEFORE_DB_RESTORE"
  echo "SQL_AFTER_DB_RESTORE: $SQL_AFTER_DB_RESTORE"
  echo "WORKLOAD_REAL: $WORKLOAD_REAL"
  echo "WORKLOAD_BASIS: $WORKLOAD_BASIS"
  echo "WORKLOAD_CUSTOM_SQL: $WORKLOAD_CUSTOM_SQL"
  echo "WORKLOAD_REAL_REPLAY_SPEED: $WORKLOAD_REAL_REPLAY_SPEED"
  echo "DELTA_SQL_DO: $DELTA_SQL_DO"
  echo "DELTA_SQL_UNDO: $DELTA_SQL_UNDO"
  echo "DELTA_CONFIG: $DELTA_CONFIG"
  echo "ARTIFACTS_DESTINATION: $ARTIFACTS_DESTINATION"
  echo "S3_CFG_PATH: $S3_CFG_PATH"
  echo "TMP_PATH: $TMP_PATH"
  echo "AWS_EBS_VOLUME_SIZE: $AWS_EBS_VOLUME_SIZE"
fi

#######################################
# Check path to file/directory.
# Globals:
#   None
# Arguments:
#   (text) name of the variable holding the
#          file path (starts with 'file://' or 's3://') or any string
# Returns:
#   (integer) for input starting with 's3://' always returns 0
#             for 'file://': 0 if file exists locally, error if it doesn't
#             1 if the input is empty,
#             -1 otherwise.
#######################################
function checkPath() {
  if [[ -z $1 ]]; then
    return 1
  fi
  eval path=\$$1
  if [[ $path =~ "s3://" ]]; then
    dbg "$1 looks like a S3 file path. Warning: Its presence will not be checked!"
    return 0 # we do not actually check S3 paths at the moment
  elif [[ $path =~ "file://" ]]; then
    dbg "$1 looks like a local file path."
    path=${path/file:\/\//}
    if [[ -f $path ]]; then
      dbg "$path found."
      eval "$1=\"$path\"" # update original variable
      return 0 # file found
    else
      err "File '$path' is not found locally."
      exit 1
    fi
  else
    dbg "Value of $2 is not a file path. Use its value as a content."
    return -1 #
  fi
}

### CLI parameters checks ###
if [[ "$RUN_ON" == "aws" ]]; then
  if [ ! -z ${CONTAINER_ID+x} ]; then
    err "ERROR: Container ID may be specified only for local runs ('--run-on localhost')."
    exit 1
  fi
  if [[ -z ${AWS_KEYPAIR_NAME+x} ]] || [[ -z ${AWS_SSH_KEY_PATH+x} ]]; then
    err "ERROR: AWS keypair name and ssh key file must be specified to run on AWS EC2."
    exit 1
  else
    checkPath AWS_SSH_KEY_PATH
  fi
  if [[ -z ${AWS_EC2_TYPE+x} ]]; then
    err "ERROR: AWS EC2 Instance type not given."
    exit 1
  fi
elif [[ "$RUN_ON" == "localhost" ]]; then
  if [[ ! -z ${AWS_KEYPAIR_NAME+x} ]] || [[ ! -z ${AWS_SSH_KEY_PATH+x} ]] ; then
    err "ERROR: options '--aws-keypair-name' and '--aws-ssh-key-path' must be used with '--run on aws'."
    exit 1
  fi
  if [[ ! -z ${AWS_EC2_TYPE+x} ]]; then
    err "ERROR: option '--aws-ec2-type' must be used with '--run on aws'."
    exit 1
  fi
  if [[ ! -z ${AWS_EBS_VOLUME_SIZE+x} ]]; then
    err "ERROR: option '--aws-ebs-volume-size' must be used with '--run on aws'."
    exit 1
  fi
else
  err "ERROR: incorrect value for option --run-on"
  exit 1
fi

if [[ -z ${PG_VERSION+x} ]]; then
  err "NOTICE: Postgres version is not specified. Will use version $POSTGRES_VERSION_DEFAULT."
  PG_VERSION="$POSTGRES_VERSION_DEFAULT"
fi

if [[ -z ${TMP_PATH+x} ]]; then
  TMP_PATH="/tmp"
  err "NOTICE: Path to tmp directory is not specified. Will use $TMP_PATH"
fi
# create $TMP_PATH directory if not found, then create a subdirectory
if [[ ! -d $TMP_PATH ]]; then
  mkdir $TMP_PATH
fi
TMP_PATH="$TMP_PATH/nancy_run_"$(date "+%Y%m%d_%H%M%S")
if [[ ! -d $TMP_PATH ]]; then
  mkdir $TMP_PATH
fi
err "NOTICE: Switched to a new sub-directory in the temp path: $TMP_PATH"

workloads_count=0
[[ ! -z ${WORKLOAD_BASIS+x} ]] && let workloads_count=$workloads_count+1
[[ ! -z ${WORKLOAD_REAL+x} ]] && let workloads_count=$workloads_count+1
[[ ! -z ${WORKLOAD_CUSTOM_SQL+x} ]] && let workloads_count=$workloads_count+1

if [[ -z ${DB_PREPARED_SNAPSHOT+x} ]]  &&  [[ -z ${DB_DUMP+x} ]]; then
  err "ERROR: The object (database) is not defined."
  exit 1;
fi

# --workload-real or --workload-basis-path or --workload-custom-sql
if [[ "$workloads_count" -eq "0" ]]; then
  err "ERROR: The workload is not defined."
  exit 1;
fi

if  [[ "$workloads_count" -gt "1" ]]; then
  err "ERROR: 2 or more workload sources are given."
  exit 1
fi

if [[ ! -z ${DB_PREPARED_SNAPSHOT+x} ]]  &&  [[ ! -z ${DB_DUMP+x} ]]; then
  err "ERROR: Both snapshot and dump sources are given."
  exit 1
fi

if [[ ! -z ${DB_DUMP+x} ]]; then
  checkPath DB_DUMP
  if [[ "$?" -ne "0" ]]; then
    echo "$DB_DUMP" > $TMP_PATH/db_dump_tmp.sql
    DB_DUMP="$TMP_PATH/db_dump_tmp.sql"
  fi
  DB_DUMP_FILENAME=$(basename $DB_DUMP)
  DB_DUMP_EXT=${DB_DUMP_FILENAME##*.}
fi

if [[ -z ${PG_CONFIG+x} ]]; then
  err "NOTICE: No PostgreSQL config is provided. Will use default."
  # TODO(NikolayS) use "auto-tuning" – shared_buffers=1/4 RAM, etc
else
  checkPath PG_CONFIG
  if [[ "$?" -ne "0" ]]; then # TODO(NikolayS) support file:// and s3://
    #err "WARNING: Value given as pg_config: '$PG_CONFIG' not found as file will use as content"
    echo "$PG_CONFIG" > $TMP_PATH/pg_config_tmp.sql
    PG_CONFIG="$TMP_PATH/pg_config_tmp.sql"
  fi
fi

if ( \
  ([[ -z ${DELTA_SQL_UNDO+x} ]] && [[ ! -z ${DELTA_SQL_DO+x} ]]) \
  || ([[ -z ${DELTA_SQL_DO+x} ]] && [[ ! -z ${DELTA_SQL_UNDO+x} ]])
); then
  err "ERROR: if '--delta-sql-do' is specified, '--delta-sql-undo' must be also specified, and vice versa."
  exit 1;
fi

if [[ -z ${ARTIFACTS_DESTINATION+x} ]]; then
  err "NOTICE: Artifacts destination is not given. Will use ./"
  ARTIFACTS_DESTINATION="."
fi

if [[ -z ${ARTIFACTS_FILENAME+x} ]]; then
  dbg "Artifacts naming is not set. Will use: '$DOCKER_MACHINE'"
  ARTIFACTS_FILENAME=$DOCKER_MACHINE
fi

if [[ ! -z ${WORKLOAD_REAL+x} ]] && ! checkPath WORKLOAD_REAL; then
  err "ERROR: workload file '$WORKLOAD_REAL' not found."
  exit 1
fi

if [[ ! -z ${WORKLOAD_BASIS+x} ]] && ! checkPath WORKLOAD_BASIS; then
  err "ERROR: workload file '$WORKLOAD_BASIS' not found."
  exit 1
fi

if [[ ! -z ${WORKLOAD_CUSTOM_SQL+x} ]]; then
  checkPath WORKLOAD_CUSTOM_SQL
  if [[ "$?" -ne "0" ]]; then
    #err "WARNING: Value given as workload-custom-sql: '$WORKLOAD_CUSTOM_SQL' not found as file will use as content"
    echo "$WORKLOAD_CUSTOM_SQL" > $TMP_PATH/workload_custom_sql_tmp.sql
    WORKLOAD_CUSTOM_SQL="$TMP_PATH/workload_custom_sql_tmp.sql"
  fi
fi

if [[ ! -z ${COMMANDS_AFTER_CONTAINER_INIT+x} ]]; then
  checkPath COMMANDS_AFTER_CONTAINER_INIT
  if [[ "$?" -ne "0" ]]; then
    #err "WARNING: Value given as after_db_init_code: '$COMMANDS_AFTER_CONTAINER_INIT' not found as file will use as content"
    echo "$COMMANDS_AFTER_CONTAINER_INIT" > $TMP_PATH/after_docker_init_code_tmp.sh
    COMMANDS_AFTER_CONTAINER_INIT="$TMP_PATH/after_docker_init_code_tmp.sh"
  fi
fi

if [[ ! -z ${SQL_AFTER_DB_RESTORE+x} ]]; then
  checkPath SQL_AFTER_DB_RESTORE
  if [[ "$?" -ne "0" ]]; then
    echo "$SQL_AFTER_DB_RESTORE" > $TMP_PATH/after_db_init_code_tmp.sql
    SQL_AFTER_DB_RESTORE="$TMP_PATH/after_db_init_code_tmp.sql"
  fi
fi

if [[ ! -z ${SQL_BEFORE_DB_RESTORE+x} ]]; then
  checkPath SQL_BEFORE_DB_RESTORE
  if [[ "$?" -ne "0" ]]; then
    #err "WARNING: Value given as before_db_init_code: '$SQL_BEFORE_DB_RESTORE' not found as file will use as content"
    echo "$SQL_BEFORE_DB_RESTORE" > $TMP_PATH/before_db_init_code_tmp.sql
    SQL_BEFORE_DB_RESTORE="$TMP_PATH/before_db_init_code_tmp.sql"
  fi
fi

if [[ ! -z ${DELTA_SQL_DO+x} ]]; then
  checkPath DELTA_SQL_DO
  if [[ "$?" -ne "0" ]]; then
    echo "$DELTA_SQL_DO" > $TMP_PATH/target_ddl_do_tmp.sql
    DELTA_SQL_DO="$TMP_PATH/target_ddl_do_tmp.sql"
  fi
fi

if [[ ! -z ${DELTA_SQL_UNDO+x} ]]; then
  checkPath DELTA_SQL_UNDO
  if [[ "$?" -ne "0" ]]; then
    echo "$DELTA_SQL_UNDO" > $TMP_PATH/target_ddl_undo_tmp.sql
    DELTA_SQL_UNDO="$TMP_PATH/target_ddl_undo_tmp.sql"
  fi
fi

if [[ ! -z ${DELTA_CONFIG+x} ]]; then
  checkPath DELTA_CONFIG
  if [[ "$?" -ne "0" ]]; then
    echo "$DELTA_CONFIG" > $TMP_PATH/target_config_tmp.conf
    DELTA_CONFIG="$TMP_PATH/target_config_tmp.conf"
  fi
fi

if [[ "$RUN_ON" == "aws" ]]; then
  if [[ ! -z ${AWS_EBS_VOLUME_SIZE+x} ]]; then
    if ! [[ $AWS_EBS_VOLUME_SIZE =~ '^[0-9]+$' ]] ; then
      err "ERROR: --ebs-volume-size must be integer."
      exit 1
    fi
  else
    if [[ ! ${AWS_EC2_TYPE:0:2} == 'i3' ]]; then
      err "NOTICE: EBS volume size is not given, will be calculated based on the dump file size (might be not enough)."
      err "WARNING: It is recommended to specify EBS volume size explicitly (CLI option '--ebs-volume-size')."
    fi
  fi
fi
### End of CLI parameters checks ###

START_TIME=$(date +%s);

# Determine dump file size
if [[ "$RUN_ON" == "aws" ]] && [[ ! ${AWS_EC2_TYPE:0:2} == "i3" ]] \
    && [[ -z ${AWS_EBS_VOLUME_SIZE+x} ]] && [[ ! -z ${DB_DUMP+x} ]]; then
  dbg "Calculate EBS volume size."
  dumpFileSize=0
  if [[ $DB_DUMP =~ "s3://" ]]; then
    dumpFileSize=$(s3cmd info $DB_DUMP | grep "File size:" )
    dumpFileSize=${dumpFileSize/File size:/}
    dumpFileSize=${dumpFileSize/\t/}
    dumpFileSize=${dumpFileSize// /}
    dbg "S3 file size: $dumpFileSize"
  elif [[ $DB_DUMP =~ "file://" ]]; then
    dumpFileSize=$(stat -c%s "$DB_DUMP" | awk '{print $1}') # TODO(NikolayS) MacOS version
    let dumpFileSize=dumpFileSize*$EBS_SIZE_MULTIPLIER
  else
    dumpFileSize=$(echo "$DB_DUMP" | wc -c)
  fi
  let minSize=50*$KB*$KB*$KB
  ebsSize=$minSize # 50 GB
  if [[ "$dumpFileSize" -gt "$minSize" ]]; then
    let ebsSize=$dumpFileSize
    ebsSize=$(numfmt --to-unit=G $ebsSize) # TODO(NikolayS) coreutils are implicitly required!!
    AWS_EBS_VOLUME_SIZE=$ebsSize
    dbg "EBS volume size: $AWS_EBS_VOLUME_SIZE GB"
  else
    msg "EBS volume is not required."
  fi
fi

set -ueo pipefail
[[ $DEBUG -eq 1 ]] && set -uox pipefail # to debug
shopt -s expand_aliases

## Docker tools
function waitEC2Ready() {
  cmd=$1
  machine=$2
  checkPrice=$3
  while true; do
    sleep 5; STOP=1
    ps ax | grep "$cmd" | grep "$machine" >/dev/null && STOP=0
    ((STOP==1)) && return 0
    if [ $checkPrice -eq 1 ]; then
      status=$( \
        aws ec2 describe-spot-instance-requests \
        --filters="Name=launch.instance-type,Values=$AWS_EC2_TYPE" \
        | jq  '.SpotInstanceRequests | sort_by(.CreateTime) | .[] | .Status.Code' \
        | tail -n 1
      )
      if [[ "$status" == "\"price-too-low\"" ]]; then
        echo "price-too-low"; # this value is result of function (not message for user), will check later
        return 0
      fi
    fi
  done
}

# Params:
#  1) machine name
#  2) AWS EC2 instance type
#  3) price
#  4) duration (minutes)
#  5) key pair name
#  6) key path
function createDockerMachine() {
  msg "Attempt to create a docker machine..."
  docker-machine create --driver=amazonec2 \
    --amazonec2-request-spot-instance \
    --amazonec2-keypair-name="$5" \
    --amazonec2-ssh-keypath="$6" \
    --amazonec2-instance-type=$2 \
    --amazonec2-spot-price=$3 \
    --amazonec2-zone $7 \
    $1 2> >(grep -v "failed waiting for successful resource state" >&2) &
#    --amazonec2-block-duration-minutes=$4 \
}

function destroyDockerMachine() {
  # If spot request wasn't fulfilled, there is no associated instance,
  # so "docker-machine rm" will show an error, which is safe to ignore.
  # We better filter it out to avoid any confusions.
  # What is used here is called "process substitution",
  # see https://www.gnu.org/software/bash/manual/bash.html#Process-Substitution
  # The same trick is used in createDockerMachine to filter out errors
  # when we have "price-too-low" attempts, such errors come in few minutes
  # after an attempt and are generally unexpected by user.
  cmdout=$(docker-machine rm --force $1 2> >(grep -v "unknown instance" >&2) )
  msg "Termination requested for machine, current status: $cmdout"
}

function cleanupAndExit {
  if  [ "$KEEP_ALIVE" -gt "0" ]; then
    msg "Debug timeout is $KEEP_ALIVE seconds – started."
    msg "  To connect to the docker machine use:"
    msg "    docker \`docker-machine config $DOCKER_MACHINE\` exec -it pg_nancy_${CURRENT_TS} bash"
    sleep $KEEP_ALIVE
  fi
  msg "Remove temp files..." # if exists
  if [[ ! -z "${dockerConfig+x}" ]]; then
    docker $dockerConfig exec -i ${containerHash} bash -c "sudo rm -rf $MACHINE_HOME"
  fi
  rm -rf "$TMP_PATH"
  if [[ "$RUN_ON" == "localhost" ]]; then
    msg "Remove docker container"
    docker container rm -f $containerHash
  elif [[ "$RUN_ON" == "aws" ]]; then
    destroyDockerMachine $DOCKER_MACHINE
    if [ ! -z ${VOLUME_ID+x} ]; then
        msg "Wait and delete volume $VOLUME_ID"
        sleep 60 # wait for the machine to be removed
        delvolout=$(aws ec2 delete-volume --volume-id $VOLUME_ID)
        msg "Volume $VOLUME_ID deleted"
    fi
  else
    err "ASSERT: must not reach this point"
    exit 1
  fi
}
trap cleanupAndExit EXIT

if [[ "$RUN_ON" == "localhost" ]]; then
  if [[ -z ${CONTAINER_ID+x} ]]; then
    containerHash=$(docker run --name="pg_nancy_${CURRENT_TS}" \
      -v $TMP_PATH:/machine_home \
      -dit "postgresmen/postgres-with-stuff:pg${PG_VERSION}" \
    )
  else
    containerHash="$CONTAINER_ID"
  fi
  dockerConfig=""
elif [[ "$RUN_ON" == "aws" ]]; then
  ## Get max price from history and apply multiplier
  # TODO detect region and/or allow to choose via options
  prices=$(
    aws --region=us-east-1 ec2 \
    describe-spot-price-history --instance-types $AWS_EC2_TYPE --no-paginate \
    --start-time=$(date +%s) --product-descriptions="Linux/UNIX (Amazon VPC)" \
    --query 'SpotPriceHistory[*].{az:AvailabilityZone, price:SpotPrice}'
  )
  minprice=$(echo $prices | jq 'min_by(.price) | .price')
  region=$(echo $prices | jq 'min_by(.price) | .az')
  region="${region/\"/}"
  region="${region/\"/}"
  minprice="${minprice/\"/}"
  minprice="${minprice/\"/}"
  zone=${region: -1}
  msg "Min price from history: $minprice in $region (zone: $zone)"
  multiplier="1.01"
  price=$(echo "$minprice * $multiplier" | bc -l)
  msg "Increased price: $price"
  EC2_PRICE=$price
  if [ -z $zone ]; then
    region='a' #default zone
  fi

  createDockerMachine $DOCKER_MACHINE $AWS_EC2_TYPE $EC2_PRICE \
    60 $AWS_KEYPAIR_NAME $AWS_SSH_KEY_PATH $zone;
  status=$(waitEC2Ready "docker-machine create" "$DOCKER_MACHINE" 1)
  if [[ "$status" == "price-too-low" ]]; then
    msg "Price $price is too low for $AWS_EC2_TYPE instance. Getting the up-to-date value from the error message..."

    #destroyDockerMachine $DOCKER_MACHINE
    # "docker-machine rm" doesn't work for "price-too-low" spot requests,
    # so we need to clean up them via aws cli interface directly
    aws ec2 describe-spot-instance-requests \
      --filters 'Name=status-code,Values=price-too-low' \
    | grep SpotInstanceRequestId | awk '{gsub(/[,"]/, "", $2); print $2}' \
    | xargs --no-run-if-empty aws ec2 cancel-spot-instance-requests \
      --spot-instance-request-ids

    corrrectPriceForLastFailedRequest=$( \
      aws ec2 describe-spot-instance-requests \
        --filters="Name=launch.instance-type,Values=$AWS_EC2_TYPE" \
      | jq  '.SpotInstanceRequests[] | select(.Status.Code == "price-too-low") | .Status.Message' \
      | grep -Eo '[0-9]+[.][0-9]+' | tail -n 1 &
    )
    if [[ ("$corrrectPriceForLastFailedRequest" != "")  &&  ("$corrrectPriceForLastFailedRequest" != "null") ]]; then
      EC2_PRICE=$corrrectPriceForLastFailedRequest
      #update docker machine name
      CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
      DOCKER_MACHINE="nancy-$CURRENT_TS"
      DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
      #try start docker machine name with new price
      msg "Attempt to create a new docker machine: $DOCKER_MACHINE with price: $EC2_PRICE."
      createDockerMachine $DOCKER_MACHINE $AWS_EC2_TYPE $EC2_PRICE \
        60 $AWS_KEYPAIR_NAME $AWS_SSH_KEY_PATH;
      waitEC2Ready "docker-machine create" "$DOCKER_MACHINE" 0;
    else
      err "$(date "+%Y-%m-%d %H:%M:%S") ERROR: Cannot determine actual price for the instance $AWS_EC2_TYPE."
      exit 1;
    fi
  fi

  msg "Check a docker machine status."
  res=$(docker-machine status $DOCKER_MACHINE 2>&1 &)
  if [[ "$res" != "Running" ]]; then
    err "Failed: Docker $DOCKER_MACHINE is NOT running."
    exit 1;
  fi
  msg "Docker $DOCKER_MACHINE is running."
  msg "  To connect docker machine use:"
  msg "    docker \`docker-machine config $DOCKER_MACHINE\` exec -it pg_nancy_${CURRENT_TS} bash"

  containerHash=$( \
    docker `docker-machine config $DOCKER_MACHINE` run \
      --name="pg_nancy_${CURRENT_TS}" \
      -v /home/ubuntu:/machine_home \
      -v /home/storage:/storage \
      -dit "postgresmen/postgres-with-stuff:pg${PG_VERSION}"
  )
  dockerConfig=$(docker-machine config $DOCKER_MACHINE)

  if [[ "${AWS_EC2_TYPE:0:2}" == "i3" ]]; then
    msg "Using high-speed NVMe SSD disks"
    # Init i3's NVMe storage, mounting one of the existing volumes to /storage
    # The following commands are to be executed in the docker machine itself,
    # not in the container.
    docker-machine ssh $DOCKER_MACHINE sudo add-apt-repository -y ppa:sbates
    docker-machine ssh $DOCKER_MACHINE "sudo apt-get update || true"
    docker-machine ssh $DOCKER_MACHINE sudo apt-get install -y nvme-cli

    docker-machine ssh $DOCKER_MACHINE "echo \"# partition table of /dev/nvme0n1\" > /tmp/nvme.part"
    docker-machine ssh $DOCKER_MACHINE "echo \"unit: sectors \" >> /tmp/nvme.part"
    docker-machine ssh $DOCKER_MACHINE "echo \"/dev/nvme0n1p1 : start=2048, size=1855466702, Id=83 \" >> /tmp/nvme.part"
    docker-machine ssh $DOCKER_MACHINE "echo \"/dev/nvme0n1p2 : start=0, size=0, Id=0 \" >> /tmp/nvme.part"
    docker-machine ssh $DOCKER_MACHINE "echo \"/dev/nvme0n1p3 : start=0, size=0, Id=0 \" >> /tmp/nvme.part"
    docker-machine ssh $DOCKER_MACHINE "echo \"/dev/nvme0n1p4 : start=0, size=0, Id=0 \" >> /tmp/nvme.part"

    docker-machine ssh $DOCKER_MACHINE "sudo sfdisk /dev/nvme0n1 < /tmp/nvme.part"
    docker-machine ssh $DOCKER_MACHINE "sudo mkfs -t ext4 /dev/nvme0n1p1"
    docker-machine ssh $DOCKER_MACHINE "sudo mount /dev/nvme0n1p1 /home/storage"
  else
    msg "Use EBS volume"
    # Create new volume and attach them for non i3 instances if needed
    if [ ! -z ${AWS_EBS_VOLUME_SIZE+x} ]; then
      msg "Create and attach a new EBS volume (size: $AWS_EBS_VOLUME_SIZE GB)"
      VOLUME_ID=$(aws ec2 create-volume --size $AWS_EBS_VOLUME_SIZE --region us-east-1 --availability-zone us-east-1a --volume-type gp2 | jq -r .VolumeId)
      INSTANCE_ID=$(docker-machine ssh $DOCKER_MACHINE curl -s http://169.254.169.254/latest/meta-data/instance-id)
      sleep 10 # wait to volume will ready
      attachResult=$(aws ec2 attach-volume --device /dev/xvdf --volume-id $VOLUME_ID --instance-id $INSTANCE_ID --region us-east-1)
      docker-machine ssh $DOCKER_MACHINE sudo mkfs.ext4 /dev/xvdf
      docker-machine ssh $DOCKER_MACHINE sudo mount /dev/xvdf /home/storage
    fi
  fi
else
  err "ASSERT: must not reach this point"
  exit 1
fi

MACHINE_HOME="/machine_home/nancy_${containerHash}"

alias docker_exec='docker $dockerConfig exec -i ${containerHash} '

docker_exec bash -c "mkdir $MACHINE_HOME && chmod a+w $MACHINE_HOME"
if [[ "$RUN_ON" == "aws" ]]; then
  docker-machine ssh $DOCKER_MACHINE "sudo chmod a+w /home/storage"
  MACHINE_HOME="$MACHINE_HOME/storage"
  docker_exec bash -c "ln -s /storage/ $MACHINE_HOME"

  msg "Move posgresql to a separate volume"
  docker_exec bash -c "sudo /etc/init.d/postgresql stop"
  sleep 2 # wait for postgres stopped
  docker_exec bash -c "sudo mv /var/lib/postgresql /storage/"
  docker_exec bash -c "ln -s /storage/postgresql /var/lib/postgresql"
  docker_exec bash -c "sudo /etc/init.d/postgresql start"
  sleep 2 # wait for postgres started
fi

function copyFile() {
  if [[ "$1" != '' ]]; then
    if [[ "$1" =~ "s3://" ]]; then # won't work for .s3cfg!
      docker_exec s3cmd sync $1 $MACHINE_HOME/
    else
      if [[ "$RUN_ON" == "localhost" ]]; then
        #ln ${1/file:\/\//} "$TMP_PATH/nancy_$containerHash/"
        # TODO: option – hard links OR regular `cp`
        docker cp ${1/file:\/\//} $containerHash:$MACHINE_HOME/
      elif [[ "$RUN_ON" == "aws" ]]; then
        docker-machine scp $1 $DOCKER_MACHINE:/home/storage
      else
        err "ASSERT: must not reach this point"
        exit 1
      fi
    fi
  fi
}

[ ! -z ${S3_CFG_PATH+x} ] && copyFile $S3_CFG_PATH \
  && docker_exec cp $MACHINE_HOME/.s3cfg /root/.s3cfg
[ ! -z ${DB_DUMP+x} ] && copyFile $DB_DUMP
[ ! -z ${PG_CONFIG+x} ] && copyFile $PG_CONFIG
[ ! -z ${DELTA_CONFIG+x} ] && copyFile $DELTA_CONFIG
[ ! -z ${DELTA_SQL_DO+x} ] && copyFile $DELTA_SQL_DO
[ ! -z ${DELTA_SQL_UNDO+x} ] && copyFile $DELTA_SQL_UNDO
[ ! -z ${WORKLOAD_CUSTOM_SQL+x} ] && copyFile $WORKLOAD_CUSTOM_SQL
[ ! -z ${WORKLOAD_REAL+x} ] && copyFile $WORKLOAD_REAL

## Apply machine features
# Dump
sleep 2 # wait for postgres up&running
OP_START_TIME=$(date +%s);
if ([ ! -z ${COMMANDS_AFTER_CONTAINER_INIT+x} ] && [ "$COMMANDS_AFTER_CONTAINER_INIT" != "" ])
then
  msg "Apply code after docker init"
  COMMANDS_AFTER_CONTAINER_INIT_FILENAME=$(basename $COMMANDS_AFTER_CONTAINER_INIT)
  copyFile $COMMANDS_AFTER_CONTAINER_INIT
  # --set ON_ERROR_STOP=on
  docker_exec bash -c "chmod +x $MACHINE_HOME/$COMMANDS_AFTER_CONTAINER_INIT_FILENAME"
  docker_exec sh $MACHINE_HOME/$COMMANDS_AFTER_CONTAINER_INIT_FILENAME
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "After docker init code has been applied for $DURATION."
fi

OP_START_TIME=$(date +%s);
if ([ ! -z ${SQL_BEFORE_DB_RESTORE+x} ] && [ "$SQL_BEFORE_DB_RESTORE" != "" ]); then
  msg "Apply sql code before db init"
  SQL_BEFORE_DB_RESTORE_FILENAME=$(basename $SQL_BEFORE_DB_RESTORE)
  copyFile $SQL_BEFORE_DB_RESTORE
  # --set ON_ERROR_STOP=on
  docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres test -b -f $MACHINE_HOME/$SQL_BEFORE_DB_RESTORE_FILENAME $VERBOSE_OUTPUT_REDIRECT"
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Before init SQL code applied for $DURATION."
fi
OP_START_TIME=$(date +%s);
msg "Restore database dump"

CPU_CNT=$(docker_exec bash -c "cat /proc/cpuinfo | grep processor | wc -l") # for execute in docker
case "$DB_DUMP_EXT" in
  sql)
    docker_exec bash -c "cat $MACHINE_HOME/$DB_DUMP_FILENAME | psql --set ON_ERROR_STOP=on -U postgres test $VERBOSE_OUTPUT_REDIRECT"
    ;;
  bz2)
    docker_exec bash -c "bzcat $MACHINE_HOME/$DB_DUMP_FILENAME | psql --set ON_ERROR_STOP=on -U postgres test $VERBOSE_OUTPUT_REDIRECT"
    ;;
  gz)
    docker_exec bash -c "zcat $MACHINE_HOME/$DB_DUMP_FILENAME | psql --set ON_ERROR_STOP=on -U postgres test $VERBOSE_OUTPUT_REDIRECT"
    ;;
  pgdmp)
    docker_exec bash -c "pg_restore -j $CPU_CNT --no-owner --no-privileges -U postgres -d test $MACHINE_HOME/$DB_DUMP_FILENAME" || true
    ;;
esac
END_TIME=$(date +%s);
DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
msg "Database dump restored for $DURATION."
# After init database sql code apply
OP_START_TIME=$(date +%s);
if ([ ! -z ${SQL_AFTER_DB_RESTORE+x} ] && [ "$SQL_AFTER_DB_RESTORE" != "" ]); then
  msg "Apply sql code after db init"
  SQL_AFTER_DB_RESTORE_FILENAME=$(basename $SQL_AFTER_DB_RESTORE)
  copyFile $SQL_AFTER_DB_RESTORE
  docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres test -b -f $MACHINE_HOME/$SQL_AFTER_DB_RESTORE_FILENAME $VERBOSE_OUTPUT_REDIRECT"
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "After init SQL code applied for $DURATION."
fi
# Apply DDL code
OP_START_TIME=$(date +%s);
if ([ ! -z ${DELTA_SQL_DO+x} ] && [ "$DELTA_SQL_DO" != "" ]); then
  msg "Apply DDL SQL code"
  DELTA_SQL_DO_FILENAME=$(basename $DELTA_SQL_DO)
  docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres test -b -f $MACHINE_HOME/$DELTA_SQL_DO_FILENAME $VERBOSE_OUTPUT_REDIRECT"
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Delta SQL \"DO\" code applied for $DURATION."
fi
# Apply initial postgres configuration
OP_START_TIME=$(date +%s);
if ([ ! -z ${PG_CONFIG+x} ] && [ "$PG_CONFIG" != "" ]); then
  msg "Apply initial postgres configuration"
  PG_CONFIG_FILENAME=$(basename $PG_CONFIG)
  docker_exec bash -c "cat $MACHINE_HOME/$PG_CONFIG_FILENAME >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
  if [ -z ${DELTA_CONFIG+x} ]
  then
    docker_exec bash -c "sudo /etc/init.d/postgresql restart"
  fi
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Initial configuration applied for $DURATION."
fi
# Apply postgres configuration
OP_START_TIME=$(date +%s);
if ([ ! -z ${DELTA_CONFIG+x} ] && [ "$DELTA_CONFIG" != "" ]); then
  msg "Apply postgres configuration"
  DELTA_CONFIG_FILENAME=$(basename $DELTA_CONFIG)
  docker_exec bash -c "cat $MACHINE_HOME/$DELTA_CONFIG_FILENAME >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
  docker_exec bash -c "sudo /etc/init.d/postgresql restart"
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Postgres configuration applied for $DURATION."
fi
#Save before workload log
msg "Save prepaparation log"
logpath=$( \
  docker_exec bash -c "psql -XtU postgres \
    -c \"select string_agg(setting, '/' order by name) from pg_settings where name in ('log_directory', 'log_filename');\" \
    | grep / | sed -e 's/^[ \t]*//'"
)
# TODO(ns) get prepare.log.gz
#docker_exec bash -c "gzip -c $logpath > $MACHINE_HOME/$ARTIFACTS_FILENAME.prepare.log.gz"
#if [[ $ARTIFACTS_DESTINATION =~ "s3://" ]]; then
#  docker_exec s3cmd put /$MACHINE_HOME/$ARTIFACTS_FILENAME.prepare.log.gz $ARTIFACTS_DESTINATION/
#else
#  docker `docker-machine config $DOCKER_MACHINE` cp $containerHash:$MACHINE_HOME/$ARTIFACTS_FILENAME.prepare.log.gz $ARTIFACTS_DESTINATION/
#fi

# Clear statistics and log
msg "Execute vacuumdb..."
docker_exec vacuumdb -U postgres test -j $CPU_CNT --analyze
docker_exec bash -c "echo '' > /var/log/postgresql/postgresql-$PG_VERSION-main.log"
# Execute workload
OP_START_TIME=$(date +%s);
msg "Execute workload..."
if [ ! -z ${WORKLOAD_REAL+x} ] && [ "$WORKLOAD_REAL" != '' ]; then
  msg "Execute pgreplay queries..."
  docker_exec psql -U postgres test -c 'create role testuser superuser login;'
  WORKLOAD_FILE_NAME=$(basename $WORKLOAD_REAL)
  if [ ! -z ${WORKLOAD_REAL_REPLAY_SPEED+x} ] && [ "$WORKLOAD_REAL_REPLAY_SPEED" != '' ]; then
    docker_exec bash -c "pgreplay -r -s $WORKLOAD_REAL_REPLAY_SPEED  $MACHINE_HOME/$WORKLOAD_FILE_NAME"
  else
    docker_exec bash -c "pgreplay -r -j $MACHINE_HOME/$WORKLOAD_FILE_NAME"
  fi
else
  if ([ ! -z ${WORKLOAD_CUSTOM_SQL+x} ] && [ "$WORKLOAD_CUSTOM_SQL" != "" ]); then
    WORKLOAD_CUSTOM_FILENAME=$(basename $WORKLOAD_CUSTOM_SQL)
    msg "Execute custom sql queries..."
    docker_exec bash -c "psql -U postgres test -E -f $MACHINE_HOME/$WORKLOAD_CUSTOM_FILENAME $VERBOSE_OUTPUT_REDIRECT"
  fi
fi
END_TIME=$(date +%s);
DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
msg "Workload executed for $DURATION."

## Get statistics
OP_START_TIME=$(date +%s);
msg "Prepare JSON log..."
docker_exec bash -c "/root/pgbadger/pgbadger \
  -j $CPU_CNT \
  --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' /var/log/postgresql/* -f stderr \
  -o $MACHINE_HOME/$ARTIFACTS_FILENAME.json" \
  2> >(grep -v "install the Text::CSV_XS" >&2)

docker_exec bash -c "gzip -c $logpath > $MACHINE_HOME/$ARTIFACTS_FILENAME.log.gz"
docker_exec bash -c "gzip -c /etc/postgresql/$PG_VERSION/main/postgresql.conf > $MACHINE_HOME/$ARTIFACTS_FILENAME.conf.gz"
msg "Save artifacts..."
if [[ $ARTIFACTS_DESTINATION =~ "s3://" ]]; then
  docker_exec s3cmd put /$MACHINE_HOME/$ARTIFACTS_FILENAME.json $ARTIFACTS_DESTINATION/
  docker_exec s3cmd put /$MACHINE_HOME/$ARTIFACTS_FILENAME.log.gz $ARTIFACTS_DESTINATION/
  docker_exec s3cmd put /$MACHINE_HOME/$ARTIFACTS_FILENAME.conf.gz $ARTIFACTS_DESTINATION/
else
  if [[ "$RUN_ON" == "localhost" ]]; then
    docker cp $containerHash:$MACHINE_HOME/$ARTIFACTS_FILENAME.json $ARTIFACTS_DESTINATION/
    docker cp $containerHash:$MACHINE_HOME/$ARTIFACTS_FILENAME.log.gz $ARTIFACTS_DESTINATION/
    docker cp $containerHash:$MACHINE_HOME/$ARTIFACTS_FILENAME.conf.gz $ARTIFACTS_DESTINATION/
    # TODO option: ln / cp
    #cp "$TMP_PATH/nancy_$containerHash/"$ARTIFACTS_FILENAME.json $ARTIFACTS_DESTINATION/
    #cp "$TMP_PATH/nancy_$containerHash/"$ARTIFACTS_FILENAME.log.gz $ARTIFACTS_DESTINATION/
  elif [[ "$RUN_ON" == "aws" ]]; then
    docker-machine scp $DOCKER_MACHINE:/home/storage/$ARTIFACTS_FILENAME.json $ARTIFACTS_DESTINATION/
    docker-machine scp $DOCKER_MACHINE:/home/storage/$ARTIFACTS_FILENAME.log.gz $ARTIFACTS_DESTINATION/
    docker-machine scp $DOCKER_MACHINE:/home/storage/$ARTIFACTS_FILENAME.conf.gz $ARTIFACTS_DESTINATION/
  else
    err "ASSERT: must not reach this point"
    exit 1
  fi
fi
END_TIME=$(date +%s);
DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
msg "Statistics got for $DURATION."

OP_START_TIME=$(date +%s);
if ([ ! -z ${DELTA_SQL_UNDO+x} ] && [ "$DELTA_SQL_UNDO" != "" ]); then
  msg "Apply DDL undo SQL code"
  DELTA_SQL_UNDO_FILENAME=$(basename $DELTA_SQL_UNDO)
  docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres test -b -f $MACHINE_HOME/$DELTA_SQL_UNDO_FILENAME $VERBOSE_OUTPUT_REDIRECT"
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Delta SQL \"UNDO\" code has been applied for $DURATION."
fi

END_TIME=$(date +%s);
DURATION=$(echo $((END_TIME-START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
echo -e "$(date "+%Y-%m-%d %H:%M:%S"): Run done for $DURATION"
echo -e "  Report: $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME.json"
echo -e "  Query log: $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME.log.gz"
echo -e "  -------------------------------------------"
echo -e "  Workload summary:"
echo -e "    Summarized query duration:\t" $(docker_exec cat /$MACHINE_HOME/$ARTIFACTS_FILENAME.json | jq '.overall_stat.queries_duration') " ms"
echo -e "    Queries:\t\t\t" $( docker_exec cat /$MACHINE_HOME/$ARTIFACTS_FILENAME.json | jq '.overall_stat.queries_number')
echo -e "    Query groups:\t\t" $(docker_exec cat /$MACHINE_HOME/$ARTIFACTS_FILENAME.json | jq '.normalyzed_info| length')
echo -e "    Errors:\t\t\t" $(docker_exec cat /$MACHINE_HOME/$ARTIFACTS_FILENAME.json | jq '.overall_stat.errors_number')
echo -e "-------------------------------------------"
