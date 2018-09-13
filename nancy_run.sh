#!/bin/bash
#
# 2018 © Nikolay Samokhvalov nikolay@samokhvalov.com
# 2018 © Postgres.ai
#
# Perform a single run of a database experiment
# Usage: use 'nancy run help' or see the corresponding code below.

# Globals (some of them can be modified below)
KB=1024
DEBUG=false
CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
DOCKER_MACHINE="nancy-$CURRENT_TS"
DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
KEEP_ALIVE=0
VERBOSE_OUTPUT_REDIRECT=" > /dev/null"
EBS_SIZE_MULTIPLIER=5
POSTGRES_VERSION_DEFAULT=10
AWS_BLOCK_DURATION=0

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
# Print values of parameters variables for a debug
# Globals:
#   All cli parameters variables
# Arguments:
#   (text) Message
# Returns:
#   None
#######################################
function dbg_cli_parameters() {
  if $DEBUG ; then
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
    echo "DB_NAME: $DB_NAME"
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
    echo "AWS_REGION: ${AWS_REGION}"
    echo "AWS_ZONE: ${AWS_ZONE}"
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
function check_path() {
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
    dbg "Value of $1 is not a file path. Use its value as a content."
    return -1 #
  fi
}

#######################################
# Check for valid cli parameters
# Globals:
#   All cli parameters variables
# Arguments:
#   None
# Returns:
#   None
#######################################
function check_cli_parameters() {
  ### Check path|value variables for empty value ###
  ([[ ! -z ${DELTA_SQL_DO+x} ]] && [[ -z $DELTA_SQL_DO ]]) && unset -v DELTA_SQL_DO
  ([[ ! -z ${DELTA_SQL_UNDO+x} ]] && [[ -z $DELTA_SQL_UNDO ]]) && unset -v DELTA_SQL_UNDO
  ([[ ! -z ${DELTA_CONFIG+x} ]] && [[ -z $DELTA_CONFIG ]]) && unset -v DELTA_CONFIG
  ([[ ! -z ${WORKLOAD_REAL+x} ]] && [[ -z $WORKLOAD_REAL ]]) && unset -v WORKLOAD_REAL
  ([[ ! -z ${WORKLOAD_BASIS+x} ]] && [[ -z $WORKLOAD_BASIS ]]) && unset -v WORKLOAD_BASIS
  ([[ ! -z ${WORKLOAD_CUSTOM_SQL+x} ]] && [[ -z $WORKLOAD_CUSTOM_SQL ]]) && unset -v WORKLOAD_CUSTOM_SQL
  ([[ ! -z ${DB_DUMP+x} ]] && [[ -z $DB_DUMP ]]) && unset -v DB_DUMP
  ([[ ! -z ${COMMANDS_AFTER_CONTAINER_INIT+x} ]] && [[ -z $COMMANDS_AFTER_CONTAINER_INIT ]]) && unset -v COMMANDS_AFTER_CONTAINER_INIT
  ([[ ! -z ${SQL_BEFORE_DB_RESTORE+x} ]] && [[ -z $SQL_BEFORE_DB_RESTORE ]]) && unset -v SQL_BEFORE_DB_RESTORE
  ([[ ! -z ${SQL_AFTER_DB_RESTORE+x} ]] && [[ -z $SQL_AFTER_DB_RESTORE ]]) && unset -v SQL_AFTER_DB_RESTORE
  ([[ ! -z ${AWS_ZONE+x} ]] && [[ -z $AWS_ZONE ]]) && unset -v AWS_ZONE
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
      check_path AWS_SSH_KEY_PATH
    fi
    if [[ -z ${AWS_EC2_TYPE+x} ]]; then
      err "ERROR: AWS EC2 Instance type not given."
      exit 1
    fi
    if [[ -z ${AWS_REGION+x} ]]; then
      err "NOTICE: AWS EC2 region not given. Will use us-east-1."
      AWS_REGION='us-east-1'
    fi
    if [[ -z ${AWS_ZONE+x} ]]; then
      err "NOTICE: AWS EC2 zone not given. Will be determined by min price."
    fi
    if [[ -z ${AWS_BLOCK_DURATION+x} ]]; then
      err "NOTICE: Container live time duration is not given. Will use 60 minutes."
      AWS_BLOCK_DURATION=60
    else
      case $AWS_BLOCK_DURATION in
        0|60|120|240|300|360)
          dbg "Container live time duration is $AWS_BLOCK_DURATION."
        ;;
        *)
          err "Container live time duration (--aws-block-duration) has wrong value: $AWS_BLOCK_DURATION. Available values of AWS spot instance duration in minutes is 60, 120, 180, 240, 300, or 360)."
          exit 1
        ;;
      esac
    fi
    if [[ ! -z ${AWS_EBS_VOLUME_SIZE+x} ]]; then
      re='^[0-9]+$'
      if ! [[ $AWS_EBS_VOLUME_SIZE =~ $re ]] ; then
        err "ERROR: --aws-ebs-volume-size must be integer."
        exit 1
      fi
    else
      if [[ ! ${AWS_EC2_TYPE:0:2} == 'i3' ]]; then
        err "NOTICE: EBS volume size is not given, will be calculated based on the dump file size (might be not enough)."
        err "WARNING: It is recommended to specify EBS volume size explicitly (CLI option '--ebs-volume-size')."
      fi
    fi
  elif [[ "$RUN_ON" == "localhost" ]]; then
    if [[ ! -z ${AWS_KEYPAIR_NAME+x} ]] || [[ ! -z ${AWS_SSH_KEY_PATH+x} ]] ; then
      err "ERROR: options '--aws-keypair-name' and '--aws-ssh-key-path' must be used with '--run-on aws'."
      exit 1
    fi
    if [[ ! -z ${AWS_EC2_TYPE+x} ]]; then
      err "ERROR: option '--aws-ec2-type' must be used with '--run-on aws'."
      exit 1
    fi
    if [[ ! -z ${AWS_EBS_VOLUME_SIZE+x} ]]; then
      err "ERROR: option '--aws-ebs-volume-size' must be used with '--run-on aws'."
      exit 1
    fi
    if [[ ! -z ${AWS_REGION+x} ]]; then
      err "ERROR: option '--aws-region' must be used with '--run-on aws'."
      exit 1
    fi
    if [[ ! -z ${AWS_ZONE+x} ]]; then
      err "ERROR: option '--aws-zone' must be used with '--run-on aws'."
      exit 1
    fi
    if [[ "$AWS_BLOCK_DURATION" != "0" ]]; then
      err "ERROR: option '--aws-block-duration' must be used with '--run-on aws'."
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
    check_path DB_DUMP
    if [[ "$?" -ne "0" ]]; then
      echo "$DB_DUMP" > $TMP_PATH/db_dump_tmp.sql
      DB_DUMP="$TMP_PATH/db_dump_tmp.sql"
    fi
    DB_DUMP_FILENAME=$(basename $DB_DUMP)
    DB_DUMP_EXT=${DB_DUMP_FILENAME##*.}
  fi

  if [[ -z ${DB_NAME+x} ]]; then
    dbg "NOTICE: Database name is not given. Will use 'test'"
    DB_NAME='test'
  fi

  if [[ -z ${PG_CONFIG+x} ]]; then
    err "NOTICE: No PostgreSQL config is provided. Will use default."
    # TODO(NikolayS) use "auto-tuning" – shared_buffers=1/4 RAM, etc
  else
    check_path PG_CONFIG
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

  if [[ ! -z ${WORKLOAD_REAL+x} ]] && ! check_path WORKLOAD_REAL; then
    err "ERROR: workload file '$WORKLOAD_REAL' not found."
    exit 1
  fi

  if [[ ! -z ${WORKLOAD_BASIS+x} ]] && ! check_path WORKLOAD_BASIS; then
    err "ERROR: workload file '$WORKLOAD_BASIS' not found."
    exit 1
  fi

  if [[ ! -z ${WORKLOAD_CUSTOM_SQL+x} ]]; then
    check_path WORKLOAD_CUSTOM_SQL
    if [[ "$?" -ne "0" ]]; then
      dbg "WARNING: Value given as workload-custom-sql: '$WORKLOAD_CUSTOM_SQL' not found as file will use as content"
      echo "$WORKLOAD_CUSTOM_SQL" > $TMP_PATH/workload_custom_sql_tmp.sql
      WORKLOAD_CUSTOM_SQL="$TMP_PATH/workload_custom_sql_tmp.sql"
    fi
  fi

  if [[ ! -z ${COMMANDS_AFTER_CONTAINER_INIT+x} ]]; then
    check_path COMMANDS_AFTER_CONTAINER_INIT
    if [[ "$?" -ne "0" ]]; then
      dbg "WARNING: Value given as after_db_init_code: '$COMMANDS_AFTER_CONTAINER_INIT' not found as file will use as content"
      echo "$COMMANDS_AFTER_CONTAINER_INIT" > $TMP_PATH/after_docker_init_code_tmp.sh
      COMMANDS_AFTER_CONTAINER_INIT="$TMP_PATH/after_docker_init_code_tmp.sh"
    fi
  fi

  if [[ ! -z ${SQL_AFTER_DB_RESTORE+x} ]]; then
    check_path SQL_AFTER_DB_RESTORE
    if [[ "$?" -ne "0" ]]; then
      echo "$SQL_AFTER_DB_RESTORE" > $TMP_PATH/after_db_init_code_tmp.sql
      SQL_AFTER_DB_RESTORE="$TMP_PATH/after_db_init_code_tmp.sql"
    fi
  fi

  if [[ ! -z ${SQL_BEFORE_DB_RESTORE+x} ]]; then
    check_path SQL_BEFORE_DB_RESTORE
    if [[ "$?" -ne "0" ]]; then
      dbg "WARNING: Value given as before_db_init_code: '$SQL_BEFORE_DB_RESTORE' not found as file will use as content"
      echo "$SQL_BEFORE_DB_RESTORE" > $TMP_PATH/before_db_init_code_tmp.sql
      SQL_BEFORE_DB_RESTORE="$TMP_PATH/before_db_init_code_tmp.sql"
    fi
  fi

  if [[ ! -z ${DELTA_SQL_DO+x} ]]; then
    check_path DELTA_SQL_DO
    if [[ "$?" -ne "0" ]]; then
      echo "$DELTA_SQL_DO" > $TMP_PATH/target_ddl_do_tmp.sql
      DELTA_SQL_DO="$TMP_PATH/target_ddl_do_tmp.sql"
    fi
  fi

  if [[ ! -z ${DELTA_SQL_UNDO+x} ]]; then
    check_path DELTA_SQL_UNDO
    if [[ "$?" -ne "0" ]]; then
      echo "$DELTA_SQL_UNDO" > $TMP_PATH/target_ddl_undo_tmp.sql
      DELTA_SQL_UNDO="$TMP_PATH/target_ddl_undo_tmp.sql"
    fi
  fi

  if [[ ! -z ${DELTA_CONFIG+x} ]]; then
    check_path DELTA_CONFIG
    if [[ "$?" -ne "0" ]]; then
      echo "$DELTA_CONFIG" > $TMP_PATH/target_config_tmp.conf
      DELTA_CONFIG="$TMP_PATH/target_config_tmp.conf"
    fi
  fi
  ### End of CLI parameters checks ###
}

### Docker tools ###

#######################################
# Create Docker machine using an AWS EC2 spot instance
# See also: https://docs.docker.com/machine/reference/create/
# Globals:
#   None
# Arguments:
#   (text) [1] Machine name
#   (text) [2] EC2 Instance type
#   (text) [3] Spot instance bid price (in dollars)
#   (int)  [4] AWS spot instance duration in minutes (60, 120, 180, 240, 300,
#              or 360)
#   (text) [5] AWS keypair to use
#   (text) [6] Path to Private Key file to use for instance
#              Matching public key with .pub extension should exist
#   (text) [7] The AWS region to launch the instance
#              (for example us-east-1, eu-central-1)
#   (text) [8] The AWS zone to launch the instance in (one of a,b,c,d,e)
# Returns:
#   None
#######################################
function create_ec2_docker_machine() {
  msg "Attempt to create a docker machine in region $7 with price $3..."
  docker-machine create --driver=amazonec2 \
    --amazonec2-request-spot-instance \
    --amazonec2-instance-type=$2 \
    --amazonec2-spot-price=$3 \
    --amazonec2-block-duration-minutes=$4 \
    --amazonec2-keypair-name="$5" \
    --amazonec2-ssh-keypath="$6" \
    --amazonec2-region="$7" \
    --amazonec2-zone="$8" \
    $1 2> >(grep -v "failed waiting for successful resource state" >&2) &
}

#######################################
# Order to destroy Docker machine (any platform)
# See also: https://docs.docker.com/machine/reference/rm/
# Globals:
#   None
# Arguments:
#   (text) Machine name
# Returns:
#   None
#######################################
function destroy_docker_machine() {
  # If spot request wasn't fulfilled, there is no associated instance,
  # so "docker-machine rm" will show an error, which is safe to ignore.
  # We better filter it out to avoid any confusions.
  # What is used here is called "process substitution",
  # see https://www.gnu.org/software/bash/manual/bash.html#Process-Substitution
  # The same trick is used in create_ec2_docker_machine() to filter out errors
  # when we have "price-too-low" attempts, such errors come in few minutes
  # after an attempt and are generally unexpected by user.
  cmdout=$(docker-machine rm --force $1 2> >(grep -v "unknown instance" >&2) )
  msg "Termination requested for machine, current status: $cmdout"
}

#######################################
# Wait until EC2 instance with Docker maching is up and running
# Globals:
#   None
# Arguments:
#   (text) Machine name
# Returns:
#   None
#######################################
function wait_ec2_docker_machine_ready() {
  local machine=$1
  local check_price=$2
  while true; do
    sleep 5;
    local stop_now=1
    ps ax | grep "docker-machine create" | grep "$machine" >/dev/null && stop_now=0
    ((stop_now==1)) && return 0
    if $check_price ; then
      status=$( \
        aws --region=$AWS_REGION ec2 describe-spot-instance-requests \
          --filters="Name=launch.instance-type,Values=$AWS_EC2_TYPE" \
        | jq  '.SpotInstanceRequests | sort_by(.CreateTime) | .[] | .Status.Code' \
        | tail -n 1
      )
      if [[ "$status" == "\"price-too-low\"" ]]; then
        echo "price-too-low"; # this value is result of function (not message for user), to be checked later
        return 0
      fi
    fi
  done
}

#######################################
# Determine EC2 spot price from history with multiplier
# Globals:
#   AWS_REGION, AWS_EC2_TYPE, EC2_PRICE
# Arguments:
#   None
# Returns:
#   None
# Result:
#   Fill AWS_ZONE and EC2_PRICE variables, update AWS_REGION.
#######################################
function determine_history_ec2_spot_price() {
  ## Get max price from history and apply multiplier
  # TODO detect region and/or allow to choose via options
  prices=$(
    aws --region=$AWS_REGION ec2 \
      describe-spot-price-history --instance-types $AWS_EC2_TYPE --no-paginate \
      --start-time=$(date +%s) --product-descriptions="Linux/UNIX (Amazon VPC)" \
      --query 'SpotPriceHistory[*].{az:AvailabilityZone, price:SpotPrice}'
  )
  if [[ ! -z ${AWS_ZONE+x} ]]; then
    # zone given by option
    price_data=$(echo $prices | jq ".[] | select(.az == \"$AWS_REGION$AWS_ZONE\")")
  else
    # zone NOT given by options, will detected from min price
    price_data=$(echo $prices | jq 'min_by(.price)')
  fi
  region=$(echo $price_data | jq '.az')
  price=$(echo $price_data | jq '.price')
  #region=$(echo $price_data | jq 'min_by(.price) | .az') #TODO(NikolayS) double-check zones&regions
  region="${region/\"/}"
  region="${region/\"/}"
  price="${price/\"/}"
  price="${price/\"/}"
  AWS_ZONE=${region:$((${#region}-1)):1}
  AWS_REGION=${region:0:$((${#region}-1))}
  msg "Min price from history: $price in $AWS_REGION (zone: $AWS_ZONE)"
  multiplier="1.01"
  price=$(echo "$price * $multiplier" | bc -l)
  msg "Increased price: $price"
  EC2_PRICE=$price
}

#######################################
# Determine actual EC2 spot price from aws error message
# Globals:
#   AWS_REGION, AWS_EC2_TYPE, EC2_PRICE
# Arguments:
#   None
# Returns:
#   None
# Result:
#   Update EC2_PRICE variable or stop script if price do not determined
#######################################
function determine_actual_ec2_spot_price() {
  aws --region=$AWS_REGION ec2 describe-spot-instance-requests \
    --filters 'Name=status-code,Values=price-too-low' \
  | grep SpotInstanceRequestId | awk '{gsub(/[,"]/, "", $2); print $2}' \
  | xargs aws --region=$AWS_REGION ec2 cancel-spot-instance-requests \
    --spot-instance-request-ids || true
  corrrectPriceForLastFailedRequest=$( \
    aws --region=$AWS_REGION ec2 describe-spot-instance-requests \
      --filters="Name=launch.instance-type,Values=$AWS_EC2_TYPE" \
    | jq  '.SpotInstanceRequests[] | select(.Status.Code == "price-too-low") | .Status.Message' \
    | grep -Eo '[0-9]+[.][0-9]+' | tail -n 1 &
  )
  if [[ ("$corrrectPriceForLastFailedRequest" != "")  &&  ("$corrrectPriceForLastFailedRequest" != "null") ]]; then
    EC2_PRICE=$corrrectPriceForLastFailedRequest
  else
    err "ERROR: Cannot determine actual price for the instance $AWS_EC2_TYPE."
    exit 1;
  fi
}

#######################################
# Mount nvme drive for i3 EC2 instances
# Globals:
#   DOCKER_MACHINE
# Arguments:
#   None
# Returns:
#   None
# Result:
#   Mount drive to /home/storage of docker machine and output drive size.
#######################################
function use_ec2_nvme_drive() {
  # Init i3's NVMe storage, mounting one of the existing volumes to /storage
  # The following commands are to be executed in the docker machine itself,
  # not in the container.
  docker-machine ssh $DOCKER_MACHINE sudo add-apt-repository -y ppa:sbates
  docker-machine ssh $DOCKER_MACHINE "sudo apt-get update || true"
  docker-machine ssh $DOCKER_MACHINE sudo apt-get install -y nvme-cli
  docker-machine ssh $DOCKER_MACHINE "sudo parted -a optimal -s /dev/nvme0n1 mklabel gpt"
  docker-machine ssh $DOCKER_MACHINE "sudo parted -a optimal -s /dev/nvme0n1 mkpart primary 0% 100%"
  docker-machine ssh $DOCKER_MACHINE "sudo mkfs.ext4 /dev/nvme0n1p1"
  docker-machine ssh $DOCKER_MACHINE "sudo mount /dev/nvme0n1p1 /home/storage"
  docker-machine ssh $DOCKER_MACHINE "sudo df -h /dev/nvme0n1p1"
}

#######################################
# Determine needed drive size to store and use database for non i3 EC2 instances.
# Globals:
#   RUN_ON, AWS_EC2_TYPE, AWS_EBS_VOLUME_SIZE, DB_DUMP, EBS_SIZE_MULTIPLIER, KB
# Arguments:
#   None
# Returns:
#   None
# Result:
#   Update value of AWS_EBS_VOLUME_SIZE variable
#######################################
function determine_ebs_drive_size() {
  # Determine dump file size
  if [[ "$RUN_ON" == "aws" ]] && [[ ! ${AWS_EC2_TYPE:0:2} == "i3" ]] \
      && [[ -z ${AWS_EBS_VOLUME_SIZE+x} ]] && [[ ! -z ${DB_DUMP+x} ]]; then
    dbg "Calculate EBS volume size."
    local dumpFileSize=0
    if [[ $DB_DUMP =~ "s3://" ]]; then
      dumpFileSize=$(s3cmd info $DB_DUMP | grep "File size:" )
      dumpFileSize=${dumpFileSize/File size:/}
      dumpFileSize=${dumpFileSize/\t/}
      dumpFileSize=${dumpFileSize// /}
      dbg "S3 file size: $dumpFileSize"
    elif [[ $DB_DUMP =~ "file://" ]]; then
      dumpFileSize=$(stat -c%s "$DB_DUMP" | awk '{print $1}') # TODO(NikolayS) MacOS version
    else
      dumpFileSize=$(echo "$DB_DUMP" | wc -c)
    fi
    let dumpFileSize=dumpFileSize*$EBS_SIZE_MULTIPLIER
    let minSize=50*$KB*$KB*$KB
    local ebsSize=$minSize # 50 GB
    if [[ "$dumpFileSize" -gt "$minSize" ]]; then
      let ebsSize=$dumpFileSize
      ebsSize=$(numfmt --to-unit=G $ebsSize) # TODO(NikolayS) coreutils are implicitly required!!
      AWS_EBS_VOLUME_SIZE=$ebsSize
      dbg "EBS volume size: $AWS_EBS_VOLUME_SIZE GB"
    else
      msg "EBS volume is not required."
    fi
  fi
}

#######################################
# Create and mount ebs drive for non i3 EC2 instances
# Globals:
#   DOCKER_MACHINE, AWS_EBS_VOLUME_SIZE, AWS_REGION, AWS_ZONE, VOLUME_ID
# Arguments:
#   None
# Returns:
#   None
# Result:
#   Create new ec2 ebs drive with size $AWS_EBS_VOLUME_SIZE in $AWS_REGION region
#   Fill  VOLUME_ID variable, mount drive to /home/storage of docker machine
#   and output drive size.
#######################################
function use_ec2_ebs_drive() {
  msg "Create and attach a new EBS volume (size: $AWS_EBS_VOLUME_SIZE GB)"
  VOLUME_ID=$(aws --region=$AWS_REGION ec2 create-volume --size $AWS_EBS_VOLUME_SIZE --availability-zone $AWS_REGION$AWS_ZONE --volume-type gp2 | jq -r .VolumeId)
  sleep 10 # wait to volume will created
  instance_id=$(docker-machine ssh $DOCKER_MACHINE curl -s http://169.254.169.254/latest/meta-data/instance-id)
  attachResult=$(aws --region=$AWS_REGION ec2 attach-volume --device /dev/xvdf --volume-id $VOLUME_ID --instance-id $instance_id)
  sleep 10 # wait to volume will attached
  docker-machine ssh $DOCKER_MACHINE sudo mkfs.ext4 /dev/xvdf
  docker-machine ssh $DOCKER_MACHINE sudo mount /dev/xvdf /home/storage
  docker-machine ssh $DOCKER_MACHINE "sudo df -h /dev/xvdf"
}

#######################################
# Wait keep alive time and stop container with EC2 intstance.
# Also delete temp drive if it was created and attached for non i3 instances.
# Globals:
#   KEEP_ALIVE, MACHINE_HOME, DOCKER_MACHINE, CURRENT_TS, VOLUME_ID
# Arguments:
#   None
# Returns:
#   None
#######################################
function cleanup_and_exit {
  if  [ "$KEEP_ALIVE" -gt "0" ]; then
    msg "Debug timeout is $KEEP_ALIVE seconds – started."
    msg "  To connect docker machine use:"
    msg "    docker-machine ssh $DOCKER_MACHINE"
    msg "  To connect container machine use:"
    msg "    docker \`docker-machine config $DOCKER_MACHINE\` exec -it pg_nancy_${CURRENT_TS} bash"
    sleep $KEEP_ALIVE
  fi
  msg "Remove temp files..." # if exists
  if [[ ! -z "${DOCKER_CONFIG+x}" ]]; then
    docker $DOCKER_CONFIG exec -i ${CONTAINER_HASH} bash -c "sudo rm -rf $MACHINE_HOME"
  fi
  rm -rf "$TMP_PATH"
  if [[ "$RUN_ON" == "localhost" ]]; then
    msg "Remove docker container"
    docker container rm -f $CONTAINER_HASH
  elif [[ "$RUN_ON" == "aws" ]]; then
    destroy_docker_machine $DOCKER_MACHINE
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

#######################################
# # # # #         MAIN        # # # # #
#######################################
# Process CLI options
while [ $# -gt 0 ]; do
  case "$1" in
    help )
      help;
    exit ;;
    -d | --debug )
      DEBUG=true;
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
    --db-name )
      DB_NAME="$2"; shift 2 ;;
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
    --aws-region )
        AWS_REGION="$2"; shift 2 ;;
    --aws-zone )
        AWS_ZONE="$2"; shift 2 ;;
    --aws-block-duration )
        AWS_BLOCK_DURATION=$2; shift 2 ;;

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

dbg_cli_parameters;

check_cli_parameters;

START_TIME=$(date +%s); #save start time

determine_ebs_drive_size;

if $DEBUG ; then
  set -xueo pipefail
else
  set -ueo pipefail
fi
shopt -s expand_aliases

trap cleanup_and_exit EXIT

if [[ "$RUN_ON" == "localhost" ]]; then
  if [[ -z ${CONTAINER_ID+x} ]]; then
    CONTAINER_HASH=$(docker run --name="pg_nancy_${CURRENT_TS}" \
      -v $TMP_PATH:/machine_home \
      -dit "postgresmen/postgres-with-stuff:pg${PG_VERSION}" \
    )
  else
    CONTAINER_HASH="$CONTAINER_ID"
  fi
  DOCKER_CONFIG=""
elif [[ "$RUN_ON" == "aws" ]]; then
  determine_history_ec2_spot_price;
  create_ec2_docker_machine $DOCKER_MACHINE $AWS_EC2_TYPE $EC2_PRICE \
    $AWS_BLOCK_DURATION $AWS_KEYPAIR_NAME $AWS_SSH_KEY_PATH $AWS_REGION $AWS_ZONE;
  status=$(wait_ec2_docker_machine_ready "$DOCKER_MACHINE" true)
  if [[ "$status" == "price-too-low" ]]; then
    msg "Price $price is too low for $AWS_EC2_TYPE instance. Getting the up-to-date value from the error message..."
    #destroy_docker_machine $DOCKER_MACHINE
    # "docker-machine rm" doesn't work for "price-too-low" spot requests,
    # so we need to clean up them via aws cli interface directly
    determine_actual_ec2_spot_price;
    #update docker machine name
    CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
    DOCKER_MACHINE="nancy-$CURRENT_TS"
    DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
    #try start docker machine name with new price
    create_ec2_docker_machine $DOCKER_MACHINE $AWS_EC2_TYPE $EC2_PRICE \
      $AWS_BLOCK_DURATION $AWS_KEYPAIR_NAME $AWS_SSH_KEY_PATH $AWS_REGION $AWS_ZONE
    wait_ec2_docker_machine_ready "$DOCKER_MACHINE" false;
  fi

  msg "Check a docker machine status."
  res=$(docker-machine status $DOCKER_MACHINE 2>&1 &)
  if [[ "$res" != "Running" ]]; then
    err "Failed: Docker $DOCKER_MACHINE is NOT running."
    exit 1;
  fi
  msg "Docker $DOCKER_MACHINE is running."
  msg "  To connect docker machine use:"
  msg "    docker-machine ssh $DOCKER_MACHINE"

  docker-machine ssh $DOCKER_MACHINE "sudo sh -c \"mkdir /home/storage\""
  if [[ "${AWS_EC2_TYPE:0:2}" == "i3" ]]; then
    msg "Using high-speed NVMe SSD disks"
    use_ec2_nvme_drive;
  else
    msg "Use EBS volume"
    # Create new volume and attach them for non i3 instances if needed
    if [ ! -z ${AWS_EBS_VOLUME_SIZE+x} ]; then
      use_ec2_ebs_drive $AWS_EBS_VOLUME_SIZE;
    fi
  fi

  CONTAINER_HASH=$( \
    docker `docker-machine config $DOCKER_MACHINE` run \
      --name="pg_nancy_${CURRENT_TS}" \
      -v /home/ubuntu:/machine_home \
      -v /home/storage:/storage \
      -v /home/basedump:/basedump \
      -dit "postgresmen/postgres-with-stuff:pg${PG_VERSION}"
  )
  DOCKER_CONFIG=$(docker-machine config $DOCKER_MACHINE)
  msg "  To connect container machine use:"
  msg "    docker \`docker-machine config $DOCKER_MACHINE\` exec -it pg_nancy_${CURRENT_TS} bash"
else
  err "ASSERT: must not reach this point"
  exit 1
fi

MACHINE_HOME="/machine_home/nancy_${CONTAINER_HASH}"

alias docker_exec='docker $DOCKER_CONFIG exec -i ${CONTAINER_HASH} '
CPU_CNT=$(docker_exec bash -c "cat /proc/cpuinfo | grep processor | wc -l") # for execute in docker

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

#######################################
# Copy file to container
# Globals:
#   MACHINE_HOME, CONTAINER_HASH, docker_exec alias
# Arguments:
#   None
# Returns:
#   None
#######################################
function copy_file() {
  if [[ "$1" != '' ]]; then
    if [[ "$1" =~ "s3://" ]]; then # won't work for .s3cfg!
      docker_exec s3cmd sync $1 $MACHINE_HOME/
    else
      if [[ "$RUN_ON" == "localhost" ]]; then
        #ln ${1/file:\/\//} "$TMP_PATH/nancy_$CONTAINER_HASH/"
        # TODO: option – hard links OR regular `cp`
        docker cp ${1/file:\/\//} $CONTAINER_HASH:$MACHINE_HOME/
      elif [[ "$RUN_ON" == "aws" ]]; then
        docker-machine scp $1 $DOCKER_MACHINE:/home/storage
      else
        err "ASSERT: must not reach this point"
        exit 1
      fi
    fi
  fi
}

#######################################
# Execute shell commands in container after it was started
# Globals:
#   COMMANDS_AFTER_CONTAINER_INIT, MACHINE_HOME,docker_exec alias
# Arguments:
#   None
# Returns:
#   None
#######################################
function apply_commands_after_container_init() {
  OP_START_TIME=$(date +%s);
  if ([ ! -z ${COMMANDS_AFTER_CONTAINER_INIT+x} ] && [ "$COMMANDS_AFTER_CONTAINER_INIT" != "" ])
  then
    msg "Apply code after docker init"
    COMMANDS_AFTER_CONTAINER_INIT_FILENAME=$(basename $COMMANDS_AFTER_CONTAINER_INIT)
    copy_file $COMMANDS_AFTER_CONTAINER_INIT
    docker_exec bash -c "chmod +x $MACHINE_HOME/$COMMANDS_AFTER_CONTAINER_INIT_FILENAME"
    docker_exec sh $MACHINE_HOME/$COMMANDS_AFTER_CONTAINER_INIT_FILENAME
    END_TIME=$(date +%s);
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "After docker init code has been applied for $DURATION."
  fi
}

#######################################
# Execute sql code before restore database
# Globals:
#   SQL_BEFORE_DB_RESTORE, MACHINE_HOME, docker_exec alias
# Arguments:
#   None
# Returns:
#   None
#######################################
function apply_sql_before_db_restore() {
  OP_START_TIME=$(date +%s);
  if ([ ! -z ${SQL_BEFORE_DB_RESTORE+x} ] && [ "$SQL_BEFORE_DB_RESTORE" != "" ]); then
    msg "Apply sql code before db init"
    SQL_BEFORE_DB_RESTORE_FILENAME=$(basename $SQL_BEFORE_DB_RESTORE)
    copy_file $SQL_BEFORE_DB_RESTORE
    # --set ON_ERROR_STOP=on
    docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres $DB_NAME -b -f $MACHINE_HOME/$SQL_BEFORE_DB_RESTORE_FILENAME $VERBOSE_OUTPUT_REDIRECT"
    END_TIME=$(date +%s);
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "Before init SQL code applied for $DURATION."
  fi
}

#######################################
# Restore database dump
# Globals:
#   DB_DUMP_EXT, DB_DUMP_FILENAME, DB_NAME, MACHINE_HOME, VERBOSE_OUTPUT_REDIRECT
# Arguments:
#   None
# Returns:
#   None
#######################################
function restore_dump() {
  OP_START_TIME=$(date +%s);
  msg "Restore database dump"
  case "$DB_DUMP_EXT" in
    sql)
      docker_exec bash -c "cat $MACHINE_HOME/$DB_DUMP_FILENAME | psql --set ON_ERROR_STOP=on -U postgres $DB_NAME $VERBOSE_OUTPUT_REDIRECT"
      ;;
    bz2)
      docker_exec bash -c "bzcat $MACHINE_HOME/$DB_DUMP_FILENAME | psql --set ON_ERROR_STOP=on -U postgres $DB_NAME $VERBOSE_OUTPUT_REDIRECT"
      ;;
    gz)
      docker_exec bash -c "zcat $MACHINE_HOME/$DB_DUMP_FILENAME | psql --set ON_ERROR_STOP=on -U postgres $DB_NAME $VERBOSE_OUTPUT_REDIRECT"
      ;;
    pgdmp)
      docker_exec bash -c "pg_restore -j $CPU_CNT --no-owner --no-privileges -U postgres -d $DB_NAME $MACHINE_HOME/$DB_DUMP_FILENAME" || true
      ;;
  esac
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Database dump restored for $DURATION."
}

#######################################
# Execute sql code after db restore
# Globals:
#   SQL_AFTER_DB_RESTORE, DB_NAME, MACHINE_HOME, VERBOSE_OUTPUT_REDIRECT, docker_exec alias
# Arguments:
#   None
# Returns:
#   None
#######################################
function apply_sql_after_db_restore() {
  # After init database sql code apply
  OP_START_TIME=$(date +%s);
  if ([ ! -z ${SQL_AFTER_DB_RESTORE+x} ] && [ "$SQL_AFTER_DB_RESTORE" != "" ]); then
    msg "Apply sql code after db init"
    SQL_AFTER_DB_RESTORE_FILENAME=$(basename $SQL_AFTER_DB_RESTORE)
    copy_file $SQL_AFTER_DB_RESTORE
    docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres $DB_NAME -b -f $MACHINE_HOME/$SQL_AFTER_DB_RESTORE_FILENAME $VERBOSE_OUTPUT_REDIRECT"
    END_TIME=$(date +%s);
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "After init SQL code applied for $DURATION."
  fi
}

#######################################
# Apply DDL code
# Globals:
#   DELTA_SQL_DO, DB_NAME, MACHINE_HOME, VERBOSE_OUTPUT_REDIRECT, docker_exec alias
# Arguments:
#   None
# Returns:
#   None
#######################################
function apply_ddl_do_code() {
  # Apply DDL code
  OP_START_TIME=$(date +%s);
  if ([ ! -z ${DELTA_SQL_DO+x} ] && [ "$DELTA_SQL_DO" != "" ]); then
    msg "Apply DDL SQL code"
    DELTA_SQL_DO_FILENAME=$(basename $DELTA_SQL_DO)
    docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres $DB_NAME -b -f $MACHINE_HOME/$DELTA_SQL_DO_FILENAME $VERBOSE_OUTPUT_REDIRECT"
    END_TIME=$(date +%s);
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "Delta SQL \"DO\" code applied for $DURATION."
  fi
}

#######################################
# Apply DDL undo code
# Globals:
#   DELTA_SQL_UNDO, DB_NAME, MACHINE_HOME, VERBOSE_OUTPUT_REDIRECT, docker_exec alias
# Arguments:
#   None
# Returns:
#   None
#######################################
function apply_ddl_undo_code() {
  OP_START_TIME=$(date +%s);
  if ([ ! -z ${DELTA_SQL_UNDO+x} ] && [ "$DELTA_SQL_UNDO" != "" ]); then
    msg "Apply DDL undo SQL code"
    DELTA_SQL_UNDO_FILENAME=$(basename $DELTA_SQL_UNDO)
    docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres $DB_NAME -b -f $MACHINE_HOME/$DELTA_SQL_UNDO_FILENAME $VERBOSE_OUTPUT_REDIRECT"
    END_TIME=$(date +%s);
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "Delta SQL \"UNDO\" code has been applied for $DURATION."
  fi
}

#######################################
# Apply initial postgres configuration
# Globals:
#   PG_CONFIG, MACHINE_HOME, docker_exec alias
# Arguments:
#   None
# Returns:
#   None
#######################################
function apply_initial_postgres_configuration() {
  # Apply initial postgres configuration
  OP_START_TIME=$(date +%s);
  if ([ ! -z ${PG_CONFIG+x} ] && [ "$PG_CONFIG" != "" ]); then
    msg "Apply initial postgres configuration"
    PG_CONFIG_FILENAME=$(basename $PG_CONFIG)
    docker_exec bash -c "cat $MACHINE_HOME/$PG_CONFIG_FILENAME >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    if [ -z ${DELTA_CONFIG+x} ]
    then
      docker_exec bash -c "sudo /etc/init.d/postgresql restart"
      sleep 10
    fi
    END_TIME=$(date +%s);
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "Initial configuration applied for $DURATION."
  fi
}

#######################################
# Apply test postgres configuration
# Globals:
#   DELTA_CONFIG, MACHINE_HOME, docker_exec alias
# Arguments:
#   None
# Returns:
#   None
#######################################
function apply_postgres_configuration() {
  # Apply postgres configuration
  OP_START_TIME=$(date +%s);
  if ([ ! -z ${DELTA_CONFIG+x} ] && [ "$DELTA_CONFIG" != "" ]); then
    msg "Apply postgres configuration"
    DELTA_CONFIG_FILENAME=$(basename $DELTA_CONFIG)
    docker_exec bash -c "cat $MACHINE_HOME/$DELTA_CONFIG_FILENAME >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    docker_exec bash -c "sudo /etc/init.d/postgresql restart"
    sleep 10
    END_TIME=$(date +%s);
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "Postgres configuration applied for $DURATION."
  fi
}

#######################################
# Prepare to start workload.
# Save restore db log, vacuumdb, clear log
# Globals:
#   ARTIFACTS_FILENAME, MACHINE_HOME, DB_NAME, docker_exec alias
# Arguments:
#   None
# Returns:
#   None
#######################################
function prepare_start_workload() {
  #Save before workload log
  msg "Save prepaparation log"
  logpath=$( \
    docker_exec bash -c "psql -XtU postgres \
      -c \"select string_agg(setting, '/' order by name) from pg_settings where name in ('log_directory', 'log_filename');\" \
      | grep / | sed -e 's/^[ \t]*//'"
  )
  docker_exec bash -c "mkdir $MACHINE_HOME/$ARTIFACTS_FILENAME"
  docker_exec bash -c "gzip -c $logpath > $MACHINE_HOME/$ARTIFACTS_FILENAME/postgresql.prepare.log.gz"

  # Clear statistics and log
  msg "Execute vacuumdb..."
  docker_exec vacuumdb -U postgres $DB_NAME -j $CPU_CNT --analyze
  docker_exec bash -c "echo '' > /var/log/postgresql/postgresql-$PG_VERSION-main.log"
}

#######################################
# Execute workload.
# Globals:
#   WORKLOAD_REAL, WORKLOAD_REAL_REPLAY_SPEED, WORKLOAD_CUSTOM_SQL, MACHINE_HOME,
#   DB_NAME, VERBOSE_OUTPUT_REDIRECT, docker_exec alias
# Arguments:
#   None
# Returns:
#   None
#######################################
function execute_workload() {
  # Execute workload
  OP_START_TIME=$(date +%s);
  msg "Execute workload..."
  if [[ ! -z ${WORKLOAD_REAL+x} ]] && [[ "$WORKLOAD_REAL" != '' ]]; then
    msg "Execute pgreplay queries..."
    docker_exec psql -U postgres $DB_NAME -c 'create role testuser superuser login;'
    WORKLOAD_FILE_NAME=$(basename $WORKLOAD_REAL)
    if [[ ! -z ${WORKLOAD_REAL_REPLAY_SPEED+x} ]] && [[ "$WORKLOAD_REAL_REPLAY_SPEED" != '' ]]; then
      docker_exec bash -c "pgreplay -r -s $WORKLOAD_REAL_REPLAY_SPEED  $MACHINE_HOME/$WORKLOAD_FILE_NAME"
    else
      docker_exec bash -c "pgreplay -r -j $MACHINE_HOME/$WORKLOAD_FILE_NAME"
    fi
  else
    if ([ ! -z ${WORKLOAD_CUSTOM_SQL+x} ] && [ "$WORKLOAD_CUSTOM_SQL" != "" ]); then
      WORKLOAD_CUSTOM_FILENAME=$(basename $WORKLOAD_CUSTOM_SQL)
      msg "Execute custom sql queries..."
      docker_exec bash -c "psql -U postgres $DB_NAME -E -f $MACHINE_HOME/$WORKLOAD_CUSTOM_FILENAME $VERBOSE_OUTPUT_REDIRECT"
    fi
  fi
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Workload executed for $DURATION."
}

#######################################
# Collect results of workload execution and save to artifact destination
# Globals:
#   CONTAINER_HASH, MACHINE_HOME, ARTIFACTS_DESTINATION, docker_exec alias
# Arguments:
#   None
# Returns:
#   None
#######################################
function collect_results() {
  ## Get statistics
  OP_START_TIME=$(date +%s);
  msg "Prepare JSON log..."
  docker_exec bash -c "/root/pgbadger/pgbadger \
    -j $CPU_CNT \
    --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' /var/log/postgresql/* -f stderr \
    -o $MACHINE_HOME/$ARTIFACTS_FILENAME/pgbadger.json" \
    2> >(grep -v "install the Text::CSV_XS" >&2)
  msg "Prepare HTML log..."
  docker_exec bash -c "/root/pgbadger/pgbadger \
    -j $CPU_CNT \
    --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' /var/log/postgresql/* -f stderr \
    -o $MACHINE_HOME/$ARTIFACTS_FILENAME/pgbadger.html" \
    2> >(grep -v "install the Text::CSV_XS" >&2)

  docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from pg_stat_archiver) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_FILENAME/pg_stat_archiver.csv"
  docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from pg_stat_bgwriter) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_FILENAME/pg_stat_bgwriter.csv"
  docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from pg_stat_database) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_FILENAME/pg_stat_database.csv"
  docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from pg_stat_database_conflicts) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_FILENAME/pg_stat_database_conflicts.csv"
  docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from pg_stat_all_tables) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_FILENAME/pg_stat_all_tables.csv"
  docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from pg_stat_xact_all_tables) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_FILENAME/pg_stat_xact_all_tables.csv"
  docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from pg_stat_all_indexes) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_FILENAME/pg_stat_all_indexes.csv"
  docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from pg_statio_all_tables) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_FILENAME/pg_statio_all_tables.csv"
  docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from pg_statio_all_indexes) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_FILENAME/pg_statio_all_indexes.csv"
  docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from pg_statio_all_sequences) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_FILENAME/pg_statio_all_sequences.csv"
  docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from pg_stat_user_functions) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_FILENAME/pg_stat_user_functions.csv"
  docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from pg_stat_xact_user_functions) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_FILENAME/pg_stat_xact_user_functions.csv"

  docker_exec bash -c "gzip -c $logpath > $MACHINE_HOME/$ARTIFACTS_FILENAME/postgresql.workload.log.gz"
  docker_exec bash -c "cp /etc/postgresql/$PG_VERSION/main/postgresql.conf $MACHINE_HOME/$ARTIFACTS_FILENAME/"
  msg "Save artifacts..."
  if [[ $ARTIFACTS_DESTINATION =~ "s3://" ]]; then
    docker_exec s3cmd --recursive put /$MACHINE_HOME/$ARTIFACTS_FILENAME $ARTIFACTS_DESTINATION/
  else
    if [[ "$RUN_ON" == "localhost" ]]; then
      docker cp $CONTAINER_HASH:$MACHINE_HOME/$ARTIFACTS_FILENAME $ARTIFACTS_DESTINATION/
    elif [[ "$RUN_ON" == "aws" ]]; then
      mkdir $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME
      docker-machine scp $DOCKER_MACHINE:/home/storage/$ARTIFACTS_FILENAME/* $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME/
    else
      err "ASSERT: must not reach this point"
      exit 1
    fi
  fi
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Statistics got for $DURATION."
}

[ ! -z ${S3_CFG_PATH+x} ] && copy_file $S3_CFG_PATH \
  && docker_exec cp $MACHINE_HOME/.s3cfg /root/.s3cfg
[ ! -z ${DB_DUMP+x} ] && copy_file $DB_DUMP
[ ! -z ${PG_CONFIG+x} ] && copy_file $PG_CONFIG
[ ! -z ${DELTA_CONFIG+x} ] && copy_file $DELTA_CONFIG
[ ! -z ${DELTA_SQL_DO+x} ] && copy_file $DELTA_SQL_DO
[ ! -z ${DELTA_SQL_UNDO+x} ] && copy_file $DELTA_SQL_UNDO
[ ! -z ${WORKLOAD_CUSTOM_SQL+x} ] && copy_file $WORKLOAD_CUSTOM_SQL
[ ! -z ${WORKLOAD_REAL+x} ] && copy_file $WORKLOAD_REAL

## Apply machine features
# Dump
sleep 2 # wait for postgres up&running

apply_commands_after_container_init;
apply_sql_before_db_restore;
restore_dump;
apply_sql_after_db_restore;
apply_ddl_do_code;
apply_initial_postgres_configuration;
apply_postgres_configuration;
prepare_start_workload;
execute_workload;
collect_results;
apply_ddl_undo_code;

END_TIME=$(date +%s);
DURATION=$(echo $((END_TIME-START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
echo -e "$(date "+%Y-%m-%d %H:%M:%S"): Run done for $DURATION"
echo -e "  JSON Report: $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME/pgbadger.json"
echo -e "  HTML Report: $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME/pgbadger.html"
echo -e "  Query log: $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME/postgresql.workload.log.gz"
echo -e "  Prepare log: $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME/postgresql.prepare.log.gz"
echo -e "  Postgresql configuration log: $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME/postgresql.conf"

echo -e "  -------------------------------------------"
echo -e "  Workload summary:"
echo -e "    Summarized query duration:\t" $(docker_exec cat $MACHINE_HOME/$ARTIFACTS_FILENAME/pgbadger.json | jq '.overall_stat.queries_duration') " ms"
echo -e "    Queries:\t\t\t" $( docker_exec cat $MACHINE_HOME/$ARTIFACTS_FILENAME/pgbadger.json | jq '.overall_stat.queries_number')
echo -e "    Query groups:\t\t" $(docker_exec cat $MACHINE_HOME/$ARTIFACTS_FILENAME/pgbadger.json | jq '.normalyzed_info| length')
echo -e "    Errors:\t\t\t" $(docker_exec cat $MACHINE_HOME/$ARTIFACTS_FILENAME/pgbadger.json | jq '.overall_stat.errors_number')
echo -e "-------------------------------------------"
