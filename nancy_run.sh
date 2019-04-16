#!/bin/bash
#
# 2018–2019 © Nikolay Samokhvalov nikolay@samokhvalov.com
# 2018–2019 © Postgres.ai
#
# Perform a single run of a database experiment
# Usage: use 'nancy run help' or see the corresponding code below.
#

# Globals (some of them can be modified below)
KB=1024
DEBUG=false
NO_OUTPUT=false
CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
DOCKER_MACHINE="nancy-$CURRENT_TS"
DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
KEEP_ALIVE=0
DURATION_WRKLD=""
VERBOSE_OUTPUT_REDIRECT=" > /dev/null"
STDERR_DST="/dev/null"
EBS_SIZE_MULTIPLIER=5
POSTGRES_VERSION_DEFAULT=11
AWS_BLOCK_DURATION=0
MSG_PREFIX=""
declare -a RUNS # i - delta_config  i+1 delta_ddl_do i+2 delta_ddl_undo

#######################################
# Attach an EBS volume containing the database backup (made with pg_basebackup)
# Globals:
#   DOCKER_MACHINE, AWS_REGION, DB_EBS_VOLUME_ID
# Arguments:
#   None
# Returns:
#   None
#######################################
function attach_db_ebs_drive() {
  docker-machine ssh $DOCKER_MACHINE "sudo sh -c \"mkdir /home/backup\""
  docker-machine ssh $DOCKER_MACHINE "wget http://s3.amazonaws.com/ec2metadata/ec2-metadata"
  docker-machine ssh $DOCKER_MACHINE "chmod u+x ec2-metadata"
  local instance_id=$(docker-machine ssh $DOCKER_MACHINE ./ec2-metadata -i)
  instance_id=${instance_id:13}
  local attach_result=$(aws --region=$AWS_REGION ec2 attach-volume \
    --device /dev/xvdc --volume-id $DB_EBS_VOLUME_ID --instance-id $instance_id)
  sleep 10
  docker-machine ssh $DOCKER_MACHINE sudo mount /dev/xvdc /home/backup
  dbg $(docker-machine ssh $DOCKER_MACHINE "sudo df -h /dev/xvdc")
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
  START_PARAMS="--run-on: ${RUN_ON}
--container-id: ${CONTAINER_ID}

--pg-version: ${PG_VERSION}
--pg-config: ${PG_CONFIG}
--pg-config_auto: ${PG_CONFIG_AUTO}

--db-prepared-snapshot: ${DB_PREPARED_SNAPSHOT}
--db-dump: ${DB_DUMP}
--db-pgbench: '${DB_PGBENCH}'
--db-ebs-volume-id: ${DB_EBS_VOLUME_ID}
--db-local-pgdata: ${DB_LOCAL_PGDATA}
--pgdata-dir: ${PGDATA_DIR}
--db-name: ${DB_NAME}
--db-expose-port: ${DB_EXPOSE_PORT}

--commands-after-container-init: ${COMMANDS_AFTER_CONTAINER_INIT}
--sql-before-db-restore: ${SQL_BEFORE_DB_RESTORE}
--sql-after-db-restore: ${SQL_AFTER_DB_RESTORE}
--workload-custom-sql: ${WORKLOAD_CUSTOM_SQL}
--workload-pgbench: '${WORKLOAD_PGBENCH}'
--workload-real: ${WORKLOAD_REAL}
--workload-real-replay-speed: ${WORKLOAD_REAL_REPLAY_SPEED}
--workload-basis: ${WORKLOAD_BASIS}
--delta-sql_do: ${DELTA_SQL_DO}
--delta-sql_undo: ${DELTA_SQL_UNDO}
--delta-config: ${DELTA_CONFIG}

--aws-ec2-type: ${AWS_EC2_TYPE}
--aws-keypair-name: $AWS_KEYPAIR_NAME
--aws-ssh-key-path: $AWS_SSH_KEY_PATH
--aws-ebs_volume_size: ${AWS_EBS_VOLUME_SIZE}
--aws-region: ${AWS_REGION}
--aws-zone: ${AWS_ZONE}
--aws-block-duration: ${AWS_BLOCK_DURATION}
--aws-zfs: ${AWS_ZFS}
--s3-cfg-path: ${S3_CFG_PATH}

--no-perf: ${NO_PERF}

--debug: ${DEBUG}
--keep-alive: ${KEEP_ALIVE}
--tmp-path: ${TMP_PATH}
--artifacts-destination: ${ARTIFACTS_DESTINATION}
--artifacts-dirname: ${ARTIFACTS_DIRNAME}
"
  if $DEBUG ; then
    echo -e "Run params:
$START_PARAMS"
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
  if ! $NO_OUTPUT; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $@"
  fi
}

#######################################
# Print an message to STDOUT without timestamp
# Globals:
#   None
# Arguments:
#   (text) Message
# Returns:
#   None
#######################################
function msg_wo_dt() {
  if ! $NO_OUTPUT; then
    echo "$@"
  fi
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
      err "ERROR: File '$path' has not been found locally."
      exit 1
    fi
  else
    dbg "Value of $1 is not a file path. Use its value as a content."
    return 255
  fi
}

#######################################
# Validate CLI parameters
# Globals:
#   Variables related to all CLI parameters
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
  ([[ ! -z ${WORKLOAD_PGBENCH+x} ]] && [[ -z $WORKLOAD_PGBENCH ]]) && unset -v WORKLOAD_PGBENCH
  ([[ ! -z ${DB_DUMP+x} ]] && [[ -z $DB_DUMP ]]) && unset -v DB_DUMP
  ([[ ! -z ${DB_PGBENCH+x} ]] && [[ -z $DB_PGBENCH ]]) && unset -v DB_PGBENCH
  ([[ ! -z ${COMMANDS_AFTER_CONTAINER_INIT+x} ]] && [[ -z $COMMANDS_AFTER_CONTAINER_INIT ]]) && unset -v COMMANDS_AFTER_CONTAINER_INIT
  ([[ ! -z ${SQL_BEFORE_DB_RESTORE+x} ]] && [[ -z $SQL_BEFORE_DB_RESTORE ]]) && unset -v SQL_BEFORE_DB_RESTORE
  ([[ ! -z ${SQL_AFTER_DB_RESTORE+x} ]] && [[ -z $SQL_AFTER_DB_RESTORE ]]) && unset -v SQL_AFTER_DB_RESTORE
  ([[ ! -z ${AWS_ZONE+x} ]] && [[ -z $AWS_ZONE ]]) && unset -v AWS_ZONE
  ([[ ! -z ${CONFIG+x} ]] && [[ -z $CONFIG ]]) && unset -v CONFIG
  ### CLI parameters checks ###
  if [[ "${RUN_ON}" == "aws" ]]; then
    if [ ! -z ${CONTAINER_ID+x} ]; then
      err "ERROR: Container ID may be specified only for local runs ('--run-on localhost')."
      exit 1
    fi
    if [[ ! -z ${DB_LOCAL_PGDATA+x} ]]; then
      err "ERROR: --db-local-pgdata may be specified only for local runs ('--run-on localhost')."
      exit 1
    fi
    if [[ ! -z ${PGDATA_DIR+x} ]]; then
      err "ERROR: --db-local-pgdata may be specified only for local runs ('--run-on localhost')."
      exit 1
    fi
    if [[ -z ${AWS_KEYPAIR_NAME+x} ]] || [[ -z ${AWS_SSH_KEY_PATH+x} ]]; then
      err "ERROR: AWS keypair name and SSH key file must be specified to run on AWS EC2."
      exit 1
    else
      check_path AWS_SSH_KEY_PATH
    fi
    if [[ -z ${AWS_EC2_TYPE+x} ]]; then
      err "ERROR: AWS EC2 Instance type is not specified."
      exit 1
    fi
    if [[ -z ${AWS_REGION+x} ]]; then
      err "NOTICE: AWS EC2 region is not specified. 'us-east-1' will be used."
      AWS_REGION='us-east-1'
    fi
    if [[ -z ${AWS_ZONE+x} ]]; then
      err "NOTICE: AWS EC2 zone is not specified. Will be determined during the price optimization process."
    fi
    if [[ -z ${AWS_ZFS+x} ]]; then
      err "NOTICE: Ext4 will be used for PGDATA."
    else
      err "NOTICE: ZFS will be used for PGDATA."
    fi
    if [[ -z ${AWS_BLOCK_DURATION+x} ]]; then
      # See https://aws.amazon.com/en/blogs/aws/new-ec2-spot-blocks-for-defined-duration-workloads/
      err "NOTICE: EC2 spot block duration is not specified. Will use 60 minutes."
      AWS_BLOCK_DURATION=60
    else
      case $AWS_BLOCK_DURATION in
        0|60|120|240|300|360)
          dbg "Container life time duration is $AWS_BLOCK_DURATION."
        ;;
        *)
          err "ERROR: The value of '--aws-block-duration' is invalid: $AWS_BLOCK_DURATION. Choose one of the following: 60, 120, 180, 240, 300, or 360."
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
        msg "It is recommended to specify EBS volume size explicitly (CLI option '--aws-ebs-volume-size')."
      fi
    fi
  elif [[ "${RUN_ON}" == "localhost" ]]; then
    if [[ ! -z ${CONTAINER_ID+x} ]] && [[ ! -z ${DB_LOCAL_PGDATA+x} ]]; then
      err "ERROR: Both --container-id and --db-local-pgdata are provided. Cannot use --db-local-pgdata with existing container."
      exit 1
    fi
    if [[ ! -z ${PGDATA_DIR+x} ]] && [[ ! -z ${DB_LOCAL_PGDATA+x} ]]; then
      err "ERROR: Both --pgdata-dir and --db-local-pgdata are provided. Cannot use --pgdata-dir with existing PGDATA path specified by --db-local-pgdata."
      exit 1
    fi
    if [[ ! -z ${AWS_KEYPAIR_NAME+x} ]] || [[ ! -z ${AWS_SSH_KEY_PATH+x} ]] ; then
      err "ERROR: Options '--aws-keypair-name' and '--aws-ssh-key-path' may be used only with '--run-on aws'."
      exit 1
    fi
    if [[ ! -z ${AWS_EC2_TYPE+x} ]]; then
      err "ERROR: Option '--aws-ec2-type' may be used only with '--run-on aws'."
      exit 1
    fi
    if [[ ! -z ${AWS_EBS_VOLUME_SIZE+x} ]]; then
      err "ERROR: Option '--aws-ebs-volume-size' may be used only with '--run-on aws'."
      exit 1
    fi
    if [[ ! -z ${AWS_REGION+x} ]]; then
      err "ERROR: Option '--aws-region' may be used only with '--run-on aws'."
      exit 1
    fi
    if [[ ! -z ${AWS_ZONE+x} ]]; then
      err "ERROR: Option '--aws-zone' may be used only with '--run-on aws'."
      exit 1
    fi
    if [[ ! -z ${AWS_ZFS+x} ]]; then
      err "ERROR: Option '--aws-zfs' may be used only with '--run-on aws'."
      exit 1
    fi
    if [[ "$AWS_BLOCK_DURATION" != "0" ]]; then
      err "ERROR: Option '--aws-block-duration' may be used only with '--run-on aws'."
      exit 1
    fi
  else
    err "ERROR: The value for option '--run-on' is invalid: ${RUN_ON}"
    exit 1
  fi

  if [[ -z ${PG_VERSION+x} ]]; then
    err "NOTICE: The Postgres version is not specified. The default will be used: ${POSTGRES_VERSION_DEFAULT}."
    PG_VERSION="$POSTGRES_VERSION_DEFAULT"
  fi

  if [[ "$PG_VERSION" = "9.6" ]]; then
    CURRENT_LSN_FUNCTION="pg_current_xlog_location()"
  else
    CURRENT_LSN_FUNCTION="pg_current_wal_lsn()"
  fi

  if [[ -z ${TMP_PATH+x} ]]; then
    TMP_PATH="/tmp"
    err "NOTICE: The directory for temporary files is not specified. Default will be used: ${TMP_PATH}."
  fi
  # create $TMP_PATH directory if not found, then create a subdirectory
  if [[ ! -d $TMP_PATH ]]; then
    mkdir $TMP_PATH
  fi
  TMP_PATH=$(mktemp -u -d "${TMP_PATH}"/nancy_run_"$(date '+%Y%m%d_%H%M%S')_XXXXX")
  if [[ ! -d $TMP_PATH ]]; then
    mkdir $TMP_PATH
  fi
  dbg "NOTICE: Switched to a new sub-directory in the tmp directory: $TMP_PATH"

  workloads_count=0
  [[ ! -z ${WORKLOAD_BASIS+x} ]] && let workloads_count=$workloads_count+1
  [[ ! -z ${WORKLOAD_REAL+x} ]] && let workloads_count=$workloads_count+1
  [[ ! -z ${WORKLOAD_CUSTOM_SQL+x} ]] && let workloads_count=$workloads_count+1
  [[ ! -z ${WORKLOAD_PGBENCH+x} ]] && let workloads_count=$workloads_count+1

  if [[ "$workloads_count" -eq "0" ]]; then
    err "ERROR: The workload is not defined."
    exit 1
  fi
  if [[ $workloads_count > 1 ]]; then
    err "ERROR: Too many kinds of workload are specified. Please specify only one."
    exit 1
  fi

  objects_count=0
  [[ ! -z ${DB_PREPARED_SNAPSHOT+x} ]] && let objects_count=$objects_count+1
  [[ ! -z ${DB_DUMP+x} ]] && let objects_count=$objects_count+1
  [[ ! -z ${DB_PGBENCH+x} ]] && let objects_count=$objects_count+1
  [[ ! -z ${DB_EBS_VOLUME_ID+x} ]] && let objects_count=$objects_count+1
  [[ ! -z ${DB_LOCAL_PGDATA+x} ]] && let objects_count=$objects_count+1

  if [[ "$objects_count" -eq "0" ]]; then
    err "ERROR: The object (database) is not defined."
    exit 1
  fi

  if [[ $objects_count > 1 ]]; then
    err "ERROR: Too many objects (ways to get PGDATA) are specified. Please specify only one."
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

  if [[ -z ${DB_EXPOSE_PORT+x} ]]; then
    DB_EXPOSE_PORT=""
  else
    DB_EXPOSE_PORT="-p $DB_EXPOSE_PORT:5432"
  fi

  if [[ -z ${PG_CONFIG+x} ]]; then
    if [[ -z ${PG_CONFIG_AUTO+x} ]]; then
      err "NOTICE: No PostgreSQL config is provided. Default will be used."
    else
      msg "Postgres config will be auto-tuned."
    fi
  else
    check_path PG_CONFIG
    if [[ "$?" -ne "0" ]]; then # TODO(NikolayS) support file:// and s3://
      #err "WARNING: Value given as pg_config: '$PG_CONFIG' not found as file will use as content"
      echo "$PG_CONFIG" > $TMP_PATH/pg_config_tmp.conf
      PG_CONFIG="$TMP_PATH/pg_config_tmp.conf"
    fi
  fi

  if [[ ! -z ${CONFIG+x} ]]; then # get config options from yml config file
    #fill runs config
    check_path CONFIG
    if [[ "$?" -ne "0" ]]; then
      err "ERROR: Runs config YML file not found."
      exit 1;
    fi
    # load and parse file
    source ${BASH_SOURCE%/*}/tools/parse_yaml.sh $CONFIG "yml_"
    # preload runs config data
    i=0
    while : ; do
      var_name_config="yml_run_"$i"_delta_config"
      delta_config=$(eval echo \$$var_name_config)
      delta_config=$(echo $delta_config | tr ";" "\n")
      var_name_ddl_do="yml_run_"$i"_delta_ddl_do"
      delta_ddl_do=$(eval echo \$$var_name_ddl_do)
      var_name_ddl_undo="yml_run_"$i"_delta_ddl_undo"
      delta_ddl_undo=$(eval echo \$$var_name_ddl_undo)
      [[ -z $delta_config ]] && [[ -z $delta_ddl_do ]] && [[ -z $delta_ddl_undo ]] && break;
      let j=$i*3
      RUNS[$j]="$delta_config"
      [[ -z $delta_config ]] && RUNS[$j]=""
      RUNS[$j+1]="$delta_ddl_do"
      [[ -z $delta_ddl_do ]] && RUNS[$j+1]=""
      RUNS[$j+2]="$delta_ddl_undo"
      [[ -z $delta_ddl_undo ]] && RUNS[$j+2]=""
      let i=i+1
    done
    # validate runs config
    runs_count=${#RUNS[*]}
    let runs_count=runs_count/3
    dbg "YML runs config count: $runs_count"
    if [[ "$runs_count" -eq "0" ]] ; then
      err "ERROR: Runs config YML file do not content valid configs."
      exit 1;
    fi
    i=0
    while : ; do
      let j=$i*3
      let d=$j+1
      let u=$j+2
      delta_config=${RUNS[$j]}
      delta_ddl_do=${RUNS[$d]}
      delta_ddl_undo=${RUNS[$u]}
      if (\
        ([[ -z $delta_ddl_do ]] && [[ ! -z $delta_ddl_undo ]]) \
        || ([[ ! -z $delta_ddl_do ]] && [[ -z $delta_ddl_undo ]])
      ); then
        err "ERROR: if 'delta_ddl_do' is specified in YML run config, 'delta_ddl_undo' must be also specified, and vice versa."
        exit 1;
      fi
      if [[ ! -z "$delta_config" ]]; then
        check_path delta_config
        if [[ "$?" -ne "0" ]]; then
          echo "$delta_config" > $TMP_PATH/target_config_tmp_$i.conf
          RUNS[$j]="$TMP_PATH/target_config_tmp_$i.conf"
        fi
      fi
      if [[ ! -z "$delta_ddl_do" ]]; then
        check_path delta_ddl_do
        if [[ "$?" -ne "0" ]]; then
          echo "$delta_ddl_do" > $TMP_PATH/target_ddl_do_tmp_$i.sql
          RUNS[$d]="$TMP_PATH/target_ddl_do_tmp_$i.sql"
        fi
      fi
      if [[ ! -z "$delta_ddl_undo" ]]; then
        check_path delta_ddl_undo
        if [[ "$?" -ne "0" ]]; then
          echo "$delta_ddl_undo" > $TMP_PATH/target_ddl_undo_tmp_$i.sql
          RUNS[$u]="$TMP_PATH/target_ddl_undo_tmp_$i.sql"
        fi
      fi
      let i=$i+1
      [[ "$i" -eq "$runs_count" ]] && break;
    done
  else # get config params from options
    if ( \
      ([[ -z ${DELTA_SQL_UNDO+x} ]] && [[ ! -z ${DELTA_SQL_DO+x} ]]) \
      || ([[ -z ${DELTA_SQL_DO+x} ]] && [[ ! -z ${DELTA_SQL_UNDO+x} ]])
    ); then
      err "ERROR: if '--delta-sql-do' is specified, '--delta-sql-undo' must be also specified, and vice versa."
      exit 1;
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
    RUNS[0]=$DELTA_CONFIG
    RUNS[1]=$DELTA_SQL_DO
    RUNS[2]=$DELTA_SQL_UNDO
  fi

  if [[ -z ${ARTIFACTS_DESTINATION+x} ]]; then
    dbg "NOTICE: Artifacts destination is not specified. Will use ./"
    ARTIFACTS_DESTINATION="."
  fi

  if [[ -z ${ARTIFACTS_DIRNAME+x} ]]; then
    dbg "Artifacts naming is not set. Will use: '$DOCKER_MACHINE'"
    ARTIFACTS_DIRNAME=$DOCKER_MACHINE
  fi

  if [[ ! -z ${WORKLOAD_REAL+x} ]] && ! check_path WORKLOAD_REAL; then
    err "ERROR: The workload file '$WORKLOAD_REAL' not found."
    exit 1
  fi

  if [[ ! -z ${WORKLOAD_BASIS+x} ]] && ! check_path WORKLOAD_BASIS; then
    err "ERROR: The workload file '$WORKLOAD_BASIS' not found."
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
  msg "Attempting to provision a Docker machine in region $7 with price $3..."
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
    sleep 5
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
  msg "Min price from history: ${price}/h in $AWS_REGION (zone: $AWS_ZONE)."
  multiplier="1.01"
  price=$(echo "$price * $multiplier" | bc -l)
  msg "Increased price: ${price}/h"
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
    exit 1
  fi
}

#######################################
# (AWS only) Use ZFS on local NVMe disk or EBS drive
# Globals:
#   DOCKER_MACHINE
# Arguments:
#   1 drive path (For example: /dev/nvme1 or /dev/xvdf)
# Return:
#   None
#######################################
function use_aws_zfs_drive (){
  drive=$1
  options=""
  if [[ $drive =~ "xvd" ]]; then
    options="-f" # for ebs drives only
  fi
  # Format volume as ZFS and tune it
  docker-machine ssh $DOCKER_MACHINE "sudo apt-get install -y zfsutils-linux"
  docker-machine ssh $DOCKER_MACHINE "sudo rm -rf /home/storage >/dev/null 2>&1 || true"
  docker-machine ssh $DOCKER_MACHINE "sudo zpool create -O compression=on \
                                           -O atime=off \
                                           -O recordsize=8k \
                                           -O logbias=throughput \
                                           -m /home/storage zpool ${drive} ${options}"
  # Set ARC size as 30% of RAM
  # get MemTotal (kB)
  local memtotal_kb=$(docker-machine ssh $DOCKER_MACHINE "grep MemTotal /proc/meminfo | awk '{print \$2}'")
  # Calculate recommended ARC size in bytes.
  local arc_size_b=$(( memtotal_kb / 100 * 30 * 1024))
  # If the calculated ARC is less than 1 GiB, then set it to 1 GiB.
  if [[ "${arc_size_b}" -lt "1073741824" ]]; then
    arc_size_b="1073741824" # 1 GiB
  fi
  # finally, change ARC MAX
  docker-machine ssh $DOCKER_MACHINE "echo ${arc_size_b} | sudo tee /sys/module/zfs/parameters/zfs_arc_max"
  docker-machine ssh $DOCKER_MACHINE "sudo cat /sys/module/zfs/parameters/zfs_arc_max"
  msg "ARC MAX has been set to ${arc_size_b} bytes."
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

  if [[ -z ${AWS_ZFS+x} ]]; then
    # Format volume as Ext4 and tune it
    docker-machine ssh $DOCKER_MACHINE "sudo mkfs.ext4 /dev/nvme0n1"
    docker-machine ssh $DOCKER_MACHINE "sudo mount -o noatime \
                                             -o data=writeback \
                                             -o barrier=0 \
                                             -o nobh \
                                             /dev/nvme0n1 /home/storage || exit 115"
  else
    use_aws_zfs_drive "/dev/nvme0n1"
  fi
  docker-machine ssh $DOCKER_MACHINE "sudo df -h /home/storage"
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
  if [[ -z ${AWS_ZFS+x} ]]; then
    docker-machine ssh $DOCKER_MACHINE sudo mkfs.ext4 /dev/xvdf
    docker-machine ssh $DOCKER_MACHINE "sudo mount -o noatime \
                                             -o data=writeback \
                                             -o barrier=0 \
                                             -o nobh \
                                             /dev/xvdf /home/storage || exit 115"
    docker-machine ssh $DOCKER_MACHINE "sudo df -h /dev/xvdf"
  else
    use_aws_zfs_drive "/dev/xvdf"
  fi
  docker-machine ssh $DOCKER_MACHINE "sudo df -h /home/storage"
}

#######################################
# Print "How to connect" instructions
# Globals:
#   DOCKER_MACHINE, CURRENT_TS, RUN_ON
# Arguments:
#   None
# Returns:
#   None
#######################################
function print_connection {
  msg_wo_dt ""
  msg_wo_dt "  =========================================================="
  if [[ "$RUN_ON" == "aws" ]]; then
    msg_wo_dt "  How to connect to the Docker machine:"
    msg_wo_dt "    docker-machine ssh ${DOCKER_MACHINE}"
    msg_wo_dt "  How to connect directly to the container:"
    msg_wo_dt "    docker \`docker-machine config ${DOCKER_MACHINE}\` exec -it pg_nancy_${CURRENT_TS} bash"
  else
    msg_wo_dt "  How to connect to the container:"
    msg_wo_dt "    docker exec -it pg_nancy_${CURRENT_TS} bash"
  fi
  msg_wo_dt "  =========================================================="
  msg_wo_dt ""
}

#######################################
# Print estimated cost of experiment for run on aws
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function calc_estimated_cost {
  if [[ "$RUN_ON" == "aws" ]]; then
    END_TIME=$(date +%s)
    DURATION=$(echo $((END_TIME-START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    echo "All runs done for $DURATION"
    let SECONDS_DURATION=$END_TIME-$START_TIME
    if [[ ! -z ${EC2_PRICE+x} ]]; then
      PRICE_PER_SECOND=$(echo "scale=10; $EC2_PRICE / 3600" | bc)
      let DURATION_SECONDS=$END_TIME-$START_TIME
      ESTIMATE_COST=$(echo "scale=10; $DURATION_SECONDS * $PRICE_PER_SECOND" | bc)
      ESTIMATE_COST=$(printf "%02.03f\n" "$ESTIMATE_COST")
    fi
    if [[ ! -z "${ESTIMATE_COST+x}" ]]; then
    echo -e "Estimated AWS cost: \$$ESTIMATE_COST"
    fi
  fi
}

#######################################
# Wait keep alive time and stop container with EC2 intstance.
# Also delete temp drive if it was created and attached for non i3 instances.
# Globals:
#   KEEP_ALIVE, MACHINE_HOME, DOCKER_MACHINE, CURRENT_TS, VOLUME_ID, DONE
# Arguments:
#   None
# Returns:
#   None
#######################################
function cleanup_and_exit {
  local exit_code="$?" # we can detect exit code here

  if  [ "$KEEP_ALIVE" -gt "0" ]; then
    msg "According to '--keep-alive', the spot instance with the container will be up for additional ${KEEP_ALIVE} seconds."
    print_connection
    sleep $KEEP_ALIVE
  fi
  msg "Removing temporary files..." # if exists
  if [[ ! -z "${DOCKER_CONFIG+x}" ]]; then
    docker $DOCKER_CONFIG exec -i ${CONTAINER_HASH} bash -c "sudo rm -rf $MACHINE_HOME"
  fi
  if [[ ! -z "${PGDATA_DIR+x}" ]]; then
    docker $DOCKER_CONFIG exec -i ${CONTAINER_HASH} bash -c "sudo /etc/init.d/postgresql stop $VERBOSE_OUTPUT_REDIRECT"
    docker $DOCKER_CONFIG exec -i ${CONTAINER_HASH} bash -c "sudo rm -rf /pgdata/* $VERBOSE_OUTPUT_REDIRECT"
  fi
  rm -rf "$TMP_PATH"
  if [[ "$RUN_ON" == "localhost" ]]; then
    msg "Remove docker container"
    out=$(docker container rm -f $CONTAINER_HASH)
  elif [[ "$RUN_ON" == "aws" ]]; then
    destroy_docker_machine $DOCKER_MACHINE
    if [ ! -z ${VOLUME_ID+x} ]; then
        msg "Wait and delete volume $VOLUME_ID"
        sleep 60 # wait for the machine to be removed
        delvolout=$(aws ec2 delete-volume --volume-id $VOLUME_ID)
        msg "Volume $VOLUME_ID deleted"
    fi
  else
    err "ERROR: (ASSERT) must not reach this point."
    exit 1
  fi
  if [[ "$exit_code" -ne "0" ]]; then
    err "Exit with error code '$exit_code'."
  fi
  exit "${exit_code}"
}

#######################################
# Determine how many CPU, RAM we have, and what kind of disks.
# Globals:
#   CPU_CNT, RAM_MB, DISK_ROTATIONAL
# Arguments:
#   None
# Returns:
#   None
#######################################
function get_system_characteristics() {
  #TODO(NikolayS) hyperthreading?
  CPU_CNT=$(docker_exec bash -c "cat /proc/cpuinfo | grep processor | wc -l")

  local ram_bytes=$( \
    docker_exec bash -c "cat /proc/meminfo | grep MemTotal | awk '{print \$2}'" \
  )
  RAM_MB=$( \
    docker_exec bash -c \
      "echo \"print round(\$(cat /proc/meminfo | grep MemTotal | awk '{print \$2}').0 / 1000, 0)\" | python" \
  )
  #TODO(NikolayS) use bc instead of python

  if [[ "$RUN_ON" == "aws" ]]; then
    if [[ "${AWS_EC2_TYPE:0:2}" == "i3" ]]; then
      DISK_ROTATIONAL=false
    else
      DISK_ROTATIONAL=true # EBS might be SSD, but here we consider them as
                           # high-latency disks (TODO(NikolayS) improve
    fi
  else
    #TODO(NikolayS) check if we work with SSD or not
    DISK_ROTATIONAL=false
  fi

  local system_info="CPU_CNT: $CPU_CNT, RAM_MB: $RAM_MB, DISK_ROTATIONAL: $DISK_ROTATIONAL"
  msg "${system_info}"

  system_info="${system_info}


=== System ===
$(docker_exec bash -c "uname -a")

$(docker_exec bash -c "lsb_release -a 2>/dev/null")

=== glibc ===
$(docker_exec bash -c "ldd --version | head -n1")

=== bash ===
$(docker_exec bash -c "bash --version | head -n1")

=== CPU ===
$(docker_exec bash -c "lscpu")

=== Memory ===
$(docker_exec bash -c "free")

=== Storage ===
$(docker_exec bash -c "df -hT")

$(docker_exec bash -c "lsblk -a")
  "

  echo "${system_info}" > "${TMP_PATH}/system_info.txt"
  echo "${START_PARAMS}" > "${TMP_PATH}/nancy_start_params.txt"
}

#######################################
# # # # #         MAIN        # # # # #
#######################################
# Process CLI options
while [ $# -gt 0 ]; do
  case "$1" in
    help )
      source ${BASH_SOURCE%/*}/help/help.sh "nancy_run"
    exit ;;
    -d | --debug )
      DEBUG=true
      VERBOSE_OUTPUT_REDIRECT=''
      STDERR_DST='/dev/stderr'
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
    --pg-config-auto )
      PG_CONFIG_AUTO="$2"; shift 2;;
    --db-prepared-snapshot )
      #Still unsupported
      DB_PREPARED_SNAPSHOT="$2"; shift 2 ;;
    --db-dump )
      DB_DUMP="$2"; shift 2 ;;
    --db-pgbench )
      DB_PGBENCH="$2"; shift 2 ;;
    --db-name )
      DB_NAME="$2"; shift 2 ;;
    --db-expose-port )
      DB_EXPOSE_PORT="$2"; shift 2 ;;
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
    --workload-pgbench )
      #s3 url|filename|content
      WORKLOAD_PGBENCH="$2"; shift 2 ;;
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
    --artifacts-dirname )
      ARTIFACTS_DIRNAME="$2"; shift 2 ;;

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
    --aws-zfs )
        AWS_ZFS=1; shift ;;
    --db-ebs-volume-id )
      DB_EBS_VOLUME_ID=$2; shift 2;;
    --db-local-pgdata )
      DB_LOCAL_PGDATA=$2; shift 2;;
    --pgdata-dir )
      PGDATA_DIR=$2; shift 2;;

    --less-output )
      DEBUG=false
      NO_OUTPUT=true
      VERBOSE_OUTPUT_REDIRECT=" > /dev/null 2>&1"
      shift ;;
    --no-pgbadger )
      NO_PGBADGER=1;  shift;;
    --no-perf )
      NO_PERF=1;  shift;;
    --s3cfg-path )
      S3_CFG_PATH="$2"; shift 2 ;;
    --config )
      CONFIG=$2; shift 2;;
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

dbg_cli_parameters

check_cli_parameters

START_TIME=$(date +%s); #save start time

determine_ebs_drive_size

if [ -n "$CIRCLE_JOB" ]; then
  IS_CIRCLE_CI=true
else
  IS_CIRCLE_CI=false
fi	

if $DEBUG ; then
  set -xueo pipefail
else
  set -ueo pipefail
fi
shopt -s expand_aliases

trap cleanup_and_exit 1 2 13 15 EXIT

if [[ "$RUN_ON" == "localhost" ]]; then
  if [[ -z ${CONTAINER_ID+x} ]]; then
    msg "Pulling the Docker image (postgresmen/postgres-nancy:${PG_VERSION})..."
    docker pull "postgresmen/postgres-nancy:${PG_VERSION}" 2>&1 \
      | grep -v Waiting \
      | grep -v Pulling \
      | grep -v Verifying \
      | grep -v "Already exists" \
      | grep -v " complete"

    if [[ ! -z ${DB_LOCAL_PGDATA+x} ]] || [[ ! -z ${PGDATA_DIR+x} ]]; then
      if [[ ! -z ${DB_LOCAL_PGDATA+x} ]]; then
        pgdata_dir=$DB_LOCAL_PGDATA
      fi
      if [[ ! -z ${PGDATA_DIR+x} ]]; then
        pgdata_dir=$PGDATA_DIR
      fi
      CONTAINER_HASH=$(docker run --cap-add SYS_ADMIN --name="pg_nancy_${CURRENT_TS}" \
        ${DB_EXPOSE_PORT} \
        -v $TMP_PATH:/machine_home \
        -v $pgdata_dir:/pgdata \
        -dit "postgresmen/postgres-nancy:${PG_VERSION}" \
      )
    else
      CONTAINER_HASH=$(docker run --cap-add SYS_ADMIN --name="pg_nancy_${CURRENT_TS}" \
        ${DB_EXPOSE_PORT} \
        -v $TMP_PATH:/machine_home \
        -dit "postgresmen/postgres-nancy:${PG_VERSION}" \
      )
    fi
  else
    CONTAINER_HASH="$CONTAINER_ID"
  fi

  print_connection

  DOCKER_CONFIG=""
  msg "Docker $CONTAINER_HASH is running."
elif [[ "$RUN_ON" == "aws" ]]; then
  determine_history_ec2_spot_price
  create_ec2_docker_machine $DOCKER_MACHINE $AWS_EC2_TYPE $EC2_PRICE \
    $AWS_BLOCK_DURATION $AWS_KEYPAIR_NAME $AWS_SSH_KEY_PATH $AWS_REGION $AWS_ZONE
  status=$(wait_ec2_docker_machine_ready "$DOCKER_MACHINE" true)
  if [[ "$status" == "price-too-low" ]]; then
    msg "Price $price is too low for $AWS_EC2_TYPE instance. Getting the up-to-date value from the error message..."
    #destroy_docker_machine $DOCKER_MACHINE
    # "docker-machine rm" doesn't work for "price-too-low" spot requests,
    # so we need to clean up them via aws cli interface directly
    determine_actual_ec2_spot_price
    #update docker machine name
    CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
    DOCKER_MACHINE="nancy-$CURRENT_TS"
    DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
    #try start docker machine name with new price
    create_ec2_docker_machine $DOCKER_MACHINE $AWS_EC2_TYPE $EC2_PRICE \
      $AWS_BLOCK_DURATION $AWS_KEYPAIR_NAME $AWS_SSH_KEY_PATH $AWS_REGION $AWS_ZONE
    wait_ec2_docker_machine_ready "$DOCKER_MACHINE" false
  fi

  dbg "Checking the status of the Docker machine..."
  res=$(docker-machine status $DOCKER_MACHINE 2>&1 &)
  if [[ "$res" != "Running" ]]; then
    err "ERROR: Docker machine $DOCKER_MACHINE is NOT running."
    exit 1
  fi

  if [[ "$RUN_ON" == "aws" ]] && [[ ! -z ${DB_EBS_VOLUME_ID+x} ]]; then
    attach_db_ebs_drive
  fi

  docker-machine ssh $DOCKER_MACHINE "sudo sh -c \"mkdir /home/storage\""
  if [[ "${AWS_EC2_TYPE:0:2}" == "i3" ]]; then
    msg "High-speed NVMe SSD will be used."
    use_ec2_nvme_drive
  else
    # Create new volume and attach them for non i3 instances if needed
    if [[ "$RUN_ON" == "aws" ]] && [[ ! -z ${AWS_EBS_VOLUME_SIZE+x} ]]; then
      msg "EBS volume will be used."
      use_ec2_ebs_drive
    else
      err "ERROR: Can't use ebs drive, drive size not specified."
    fi
  fi

  DOCKER_CONFIG=$(docker-machine config $DOCKER_MACHINE)

  docker $DOCKER_CONFIG pull "postgresmen/postgres-nancy:${PG_VERSION}" 2>&1 \
    | grep -e 'Pulling from' -e Digest -e Status -e Error

  CONTAINER_HASH=$( \
    docker $DOCKER_CONFIG run \
      --name="pg_nancy_${CURRENT_TS}" \
      --privileged \
      -v /home/ubuntu:/machine_home \
      -v /home/storage:/storage \
      -v /home/backup:/backup \
      -dit "postgresmen/postgres-nancy:${PG_VERSION}"
  )

  print_connection
else
  err "ERROR: (ASSERT) must not reach this point."
  exit 1
fi

MACHINE_HOME="/machine_home/nancy_${CONTAINER_HASH}"

alias docker_exec='docker $DOCKER_CONFIG exec -i ${CONTAINER_HASH} '
get_system_characteristics

#######################################
# Stop postgres and wait for complete stop
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function stop_postgres {
  dbg "Stopping Postgres..."
  local cnt=0
  while true; do
    res=$(docker_exec bash -c "ps auxww | grep postgres | grep -v "grep" 2>/dev/null || echo ''")
    if [[ -z "$res" ]]; then
      # postgres process not found
      dbg "Postgres stopped."
      return;
    fi
    cnt=$((cnt+1))
    if [[ "${cnt}" -ge "900" ]]; then
      msg "WARNING: could not stop Postgres in 15 minutes. Killing."
      docker_exec bash -c "sudo killall -s 9 postgres || true"
    fi
    # Try normal "fast stop"
    docker_exec bash -c "sudo pg_ctlcluster ${PG_VERSION} main stop -m f || true"
    sleep 1
  done
}

#######################################
# Start postgres and wait for ready
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function start_postgres {
  dbg "Starting Postgres..."
  local cnt=0
  while true; do
    res=$(docker_exec bash -c "psql -Upostgres -d postgres -t -c \"select 1\" 2>/dev/null || echo '' ")
    if [[ ! -z "$res" ]]; then
      dbg "Postgres started."
      return;
    fi
    cnt=$((cnt+1))
    if [[ "${cnt}" -ge "900" ]]; then
      dbg "WARNING: Can't start Postgres in 15 minutes." >&2
      return 12
    fi
    docker_exec bash -c "sudo pg_ctlcluster ${PG_VERSION} main start || true"
    sleep 1
  done
  dbg "Postgres started"
}

#######################################
# Extract the database backup from the attached EBS volume.
# Globals:
#   PG_VERSION
# Arguments:
#   target directory
# Returns:
#   None
#######################################
function cp_db_ebs_backup() {
  local target=$1
  if [[ -z "$target" ]]; then
    target="/storage/postgresql/$PG_VERSION/main"
  fi

  # Here we think that postgres stopped
  msg "Extracting PGDATA from the EBS volume..."
  docker_exec bash -c "rm -rf $target/*"

  local op_start_time=$(date +%s)
  docker_exec bash -c "rm -rf $target/*"
  local result=$(docker_exec bash -c "([[ -f /backup/base.tar.gz ]] \
    && tar -C $target/ -xzvf /backup/base.tar.gz) || true")
  result=$(docker_exec bash -c "([[ -f /backup/base.tar ]] \
    && tar -C $target/ -xvf /backup/base.tar) || true")

  result=$(docker_exec bash -c "([[ -f /backup/pg_xlog.tar.gz ]] \
    && tar -C $target/pg_xlog -xzvf /backup/pg_xlog.tar.gz) || true")
  result=$(docker_exec bash -c "([[ -f /backup/pg_xlog.tar ]] \
    && tar -C $target/pg_xlog -xvf /backup/pg_xlog.tar) || true")

  result=$(docker_exec bash -c "([[ -f /backup/pg_wal.tar.gz ]] \
    && tar -C $target/pg_xlog -xzvf /backup/pg_wal.tar.gz) || true")
  result=$(docker_exec bash -c "([[ -f /backup/pg_wal.tar ]] \
    && tar -C $target/pg_wal -xvf /backup/pg_wal.tar) || true")

  local end_time=$(date +%s)
  local duration=$(echo $((end_time-op_start_time)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Time taken to extract PGDATA from the EBS volume: $duration."

  docker_exec bash -c "chown -R postgres:postgres $target"
  docker_exec bash -c "localedef -f UTF-8 -i en_US en_US.UTF-8"
  docker_exec bash -c "localedef -f UTF-8 -i ru_RU ru_RU.UTF-8"
}

#######################################
# Copy pgdata from temp location to postgres localtion
# Globals:
#   PG_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
function apply_backup(){
  # Here we think that postgres stopped
  msg "Restore(cp) database from backup."
  docker_exec bash -c "rm -rf /var/lib/postgresql/9.6/main/*"

  OP_START_TIME=$(date +%s);
  docker_exec bash -c "rm -rf /var/lib/postgresql/$PG_VERSION/main/*" || true
  docker_exec bash -c "cp -r -p -f /storage/backup/* /storage/postgresql/$PG_VERSION/main/" || true
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "PGDATA applied copied for $DURATION."

  OP_START_TIME=$(date +%s);
  docker_exec bash -c "chown -R postgres:postgres /storage/postgresql/$PG_VERSION/main/*" || true
  docker_exec bash -c "chown -R postgres:postgres /storage/postgresql/$PG_VERSION/main" || true
  docker_exec bash -c "chmod 0700 /var/lib/postgresql/$PG_VERSION/main/" || true
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Rights changed for $DURATION."
}

#######################################
# Update pgdata from temp location to postgres localtion
# Globals:
#   PG_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
function rsync_backup(){
  msg "Restore(rsync) database from backup."
  stop_postgres
  OP_START_TIME=$(date +%s);
  docker_exec bash -c "rsync -av /storage/backup/pgdata/ /storage/postgresql/$PG_VERSION/main" || true
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "pg_base main rsync done for $DURATION."

  docker_exec bash -c "chown -R postgres:postgres /storage/postgresql/$PG_VERSION/main/*" || true
  docker_exec bash -c "chown -R postgres:postgres /storage/postgresql/$PG_VERSION/main" || true
  docker_exec bash -c "chown -R postgres:postgres /var/lib/postgresql" || true
  docker_exec bash -c "chmod 0700 /var/lib/postgresql/$PG_VERSION/main/" || true

  start_postgres

  if [[ ! -z ${DB_EBS_VOLUME_ID+x} ]] && [[ ! -z ${ORIGINAL_DB_NAME+x} ]] && [[ ! "$ORIGINAL_DB_NAME" == "test" ]]; then
    docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres -c 'drop database if exists test;'"
    docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres -c 'alter database $ORIGINAL_DB_NAME rename to test;'"
  fi
}

#######################################
# Copy pgdata to postgres localtion
# Globals:
#   PG_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
function attach_pgdata() {
  local use_existing_pgdata=$1
  local op_start_time=$(date +%s)
  docker_exec bash -c "sudo /etc/init.d/postgresql stop $VERBOSE_OUTPUT_REDIRECT"
  if $use_existing_pgdata ; then
    # PGDATA path given by --db-local-pgdata
    docker_exec bash -c "sudo rm -rf /var/lib/postgresql/$PG_VERSION/main $VERBOSE_OUTPUT_REDIRECT"
    docker_exec bash -c "ln -s /pgdata/ /var/lib/postgresql/$PG_VERSION/main $VERBOSE_OUTPUT_REDIRECT"
  else
    # Working location for PGDATA is provided by --pgdata-dir
    docker_exec bash -c "sudo rm -rf /pgdata/*"
    docker_exec bash -c "sudo mv /var/lib/postgresql/$PG_VERSION/main/* /pgdata/"
    docker_exec bash -c "sudo rm -rf /var/lib/postgresql/$PG_VERSION/main"
    docker_exec bash -c "ln -s /pgdata/ /var/lib/postgresql/$PG_VERSION/main $VERBOSE_OUTPUT_REDIRECT"
  fi
  docker_exec bash -c "sudo chown -R postgres:postgres /var/lib/postgresql/$PG_VERSION/main $VERBOSE_OUTPUT_REDIRECT"
  docker_exec bash -c "sudo chmod -R 0700 /var/lib/postgresql/$PG_VERSION/main $VERBOSE_OUTPUT_REDIRECT"
  docker_exec bash -c "sudo chown -R postgres:postgres /pgdata"
  docker_exec bash -c "sudo chmod -R 0700 /pgdata"
  local end_time=$(date +%s);
  local duration=$(echo $((end_time-op_start_time)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Time taken to attach PGDATA: $duration."
  stop_postgres
  start_postgres
}

#######################################
# Detach EBS volume
# Globals:
#   DOCKER_MACHINE, DB_EBS_VOLUME_ID, AWS_REGION
# Arguments:
#   None
# Returns:
#   None
#######################################
function dettach_db_ebs_drive() {
  docker_exec bash -c "umount /backup"
  docker-machine ssh $DOCKER_MACHINE sudo umount /home/backup
  local dettach_result=$(aws --region=$AWS_REGION ec2 detach-volume --volume-id $DB_EBS_VOLUME_ID)
}

docker_exec bash -c "mkdir ${MACHINE_HOME} && chmod a+w ${MACHINE_HOME}"
if [[ "$RUN_ON" == "aws" ]]; then
  docker-machine ssh $DOCKER_MACHINE "sudo chmod a+w /home/storage"
  MACHINE_HOME="${MACHINE_HOME}/storage"
  docker_exec bash -c "ln -s /storage/ ${MACHINE_HOME}"
  #docker_exec bash -c "mkdir -p ${MACHINE_HOME}/storage"

  msg "Move PGDATA to /storage (machine's /home/storage)..."
  stop_postgres
  #docker_exec bash -c "sudo /etc/init.d/postgresql stop ${VERBOSE_OUTPUT_REDIRECT}"
  #sleep 10 # wait for postgres stopped
  docker_exec bash -c "sudo mv /var/lib/postgresql /storage/"
  docker_exec bash -c "ln -s /storage/postgresql /var/lib/postgresql"

  if [[ ! -z ${DB_EBS_VOLUME_ID+x} ]]; then
    runs_count=${#RUNS[*]}
    if [[ "$runs_count" -gt "3" ]] && [[ -z ${AWS_ZFS+x} ]]; then
      docker_exec bash -c "mkdir -p /storage/backup/pgdata"
      cp_db_ebs_backup /storage/backup
      apply_backup
    else
      cp_db_ebs_backup
    fi
    dettach_db_ebs_drive
  fi

  start_postgres
else
  if [[ ! -z ${DB_LOCAL_PGDATA+x} ]]; then
    attach_pgdata true
  else
    if [[ ! -z ${PGDATA_DIR+x} ]]; then
      attach_pgdata false
    fi
  fi
fi

LOG_PATH=$( \
  docker_exec bash -c "psql -XtU postgres \
    -c \"select string_agg(setting, '/' order by name) from pg_settings where name in ('log_directory', 'log_filename');\" \
    | grep / | sed -e 's/^[ \t]*//'"
)
if [[ -z "$LOG_PATH" ]]; then
  LOG_PATH=/var/log/postgresql/postgresql-$PG_VERSION-main.log
fi

#######################################
# Copy a file to the container
# Globals:
#   MACHINE_HOME, CONTAINER_HASH
# Arguments:
#   1 - file path
# Returns:
#   None
#######################################
function copy_file() {
  local out
  if [[ "$1" != '' ]]; then
    if [[ "$1" =~ "s3://" ]]; then # won't work for .s3cfg!
      out=$(docker_exec s3cmd sync $1 $MACHINE_HOME/ 2>&1)
    else
      if [[ "$RUN_ON" == "localhost" ]]; then
        #ln ${1/file:\/\//} "$TMP_PATH/nancy_$CONTAINER_HASH/"
        # TODO: option – hard links OR regular `cp`
        out=$(docker cp ${1/file:\/\//} $CONTAINER_HASH:$MACHINE_HOME/ 2>&1)
      elif [[ "$RUN_ON" == "aws" ]]; then
        out=$(docker-machine scp $1 $DOCKER_MACHINE:/home/storage 2>&1)
      else
        err "ERROR: (ASSERT) must not reach this point."
        exit 1
      fi
    fi
  fi
}

#######################################
# Execute shell commands in container after it started
# Globals:
#   COMMANDS_AFTER_CONTAINER_INIT, MACHINE_HOME
# Arguments:
#   None
# Returns:
#   None
#######################################
function apply_commands_after_container_init() {
  OP_START_TIME=$(date +%s)
  if ([ ! -z ${COMMANDS_AFTER_CONTAINER_INIT+x} ] && [ "$COMMANDS_AFTER_CONTAINER_INIT" != "" ])
  then
    msg "Apply code after docker init"
    COMMANDS_AFTER_CONTAINER_INIT_FILENAME=$(basename $COMMANDS_AFTER_CONTAINER_INIT)
    copy_file $COMMANDS_AFTER_CONTAINER_INIT
    docker_exec bash -c "chmod +x ${MACHINE_HOME}/${COMMANDS_AFTER_CONTAINER_INIT_FILENAME}"
    output=$(docker_exec sh $MACHINE_HOME/$COMMANDS_AFTER_CONTAINER_INIT_FILENAME)
    END_TIME=$(date +%s)
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "Time taken to apply \"after-docker-init code\": $DURATION."
  fi
}

#######################################
# Execute SQL code before database restore
# Globals:
#   SQL_BEFORE_DB_RESTORE, MACHINE_HOME
# Arguments:
#   None
# Returns:
#   None
#######################################
function apply_sql_before_db_restore() {
  OP_START_TIME=$(date +%s)
  if ([ ! -z ${SQL_BEFORE_DB_RESTORE+x} ] && [ "$SQL_BEFORE_DB_RESTORE" != "" ]); then
    msg "Applying SQL code before database initialization..."
    SQL_BEFORE_DB_RESTORE_FILENAME=$(basename $SQL_BEFORE_DB_RESTORE)
    copy_file $SQL_BEFORE_DB_RESTORE
    # --set ON_ERROR_STOP=on
    docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres ${DB_NAME} -b -f ${MACHINE_HOME}/${SQL_BEFORE_DB_RESTORE_FILENAME} ${VERBOSE_OUTPUT_REDIRECT}"
    END_TIME=$(date +%s)
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "Time taken to apply \"before-init-SQL code\": $DURATION."
  fi
}

#######################################
# Restore database from dump or generate it with pgbench
# Globals:
#   DB_DUMP_EXT, DB_DUMP_FILENAME, DB_NAME, MACHINE_HOME, VERBOSE_OUTPUT_REDIRECT
# Arguments:
#   None
# Returns:
#   None
#######################################
function restore_dump() {
  OP_START_TIME=$(date +%s)
  msg "Restoring database from dump..."
  if ([ ! -z ${DB_PGBENCH+x} ]); then
    docker_exec bash -c "pgbench -i --quiet ${DB_PGBENCH} -U postgres ${DB_NAME} ${VERBOSE_OUTPUT_REDIRECT}" || true
  else
    case "${DB_DUMP_EXT}" in
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
  fi
  stop_postgres
  start_postgres
  END_TIME=$(date +%s)
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Time taken to restore database: $DURATION."
}

#######################################
# Execute SQL code after database restore
# Globals:
#   SQL_AFTER_DB_RESTORE, DB_NAME, MACHINE_HOME, VERBOSE_OUTPUT_REDIRECT
# Arguments:
#   None
# Returns:
#   None
#######################################
function apply_sql_after_db_restore() {
  OP_START_TIME=$(date +%s)
  if ([ ! -z ${SQL_AFTER_DB_RESTORE+x} ] && [ "$SQL_AFTER_DB_RESTORE" != "" ]); then
    msg "Applying SQL code after database initialization..."
    SQL_AFTER_DB_RESTORE_FILENAME=$(basename $SQL_AFTER_DB_RESTORE)
    copy_file $SQL_AFTER_DB_RESTORE
    docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres $DB_NAME -b -f $MACHINE_HOME/$SQL_AFTER_DB_RESTORE_FILENAME $VERBOSE_OUTPUT_REDIRECT"
    END_TIME=$(date +%s)
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "Time taken to apply \"after-init-SQL code\": $DURATION."
  fi
}

#######################################
# Apply delta SQL "DO" code
# Globals:
#   DELTA_SQL_DO, DB_NAME, MACHINE_HOME, VERBOSE_OUTPUT_REDIRECT
# Arguments:
#   1 - path to file with ddl do code
# Returns:
#   None
#######################################
function apply_ddl_do_code() {
  local delta_ddl_do=$1
  # Apply delta SQL "DO" code
  OP_START_TIME=$(date +%s);
  if ([[ ! -z "$delta_ddl_do" ]] && [[ "$delta_ddl_do" != "" ]]); then
    msg "Applying delta SQL \"DO\" code..."
    delta_ddl_do_filename=$(basename $delta_ddl_do)
    docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres $DB_NAME -b -f $MACHINE_HOME/$delta_ddl_do_filename $VERBOSE_OUTPUT_REDIRECT"
    END_TIME=$(date +%s);
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "Time taken to apply delta SQL \"DO\" code: $DURATION."
  fi
}

#######################################
# Apply delta SQL "UNDO" code
# Globals:
#   DELTA_SQL_UNDO, DB_NAME, MACHINE_HOME, VERBOSE_OUTPUT_REDIRECT
# Arguments:
#   1 - path to file with delta SQL undo code
# Returns:
#   None
#######################################
function apply_ddl_undo_code() {
  local delta_ddl_undo=$1
  OP_START_TIME=$(date +%s);
  if ([[ ! -z ${delta_ddl_undo+x} ]] && [[ "$delta_ddl_undo" != "" ]]); then
    msg "Applying delta SQL \"UNDO\" code..."
    delta_ddl_undo_filename=$(basename $delta_ddl_undo)
    docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres $DB_NAME -b -f $MACHINE_HOME/$delta_ddl_undo_filename $VERBOSE_OUTPUT_REDIRECT"
    END_TIME=$(date +%s);
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "Time taken to apply delta SQL \"UNDO\" code: $DURATION."
  fi
}

#######################################
# Apply initial Postgres configuration
# Globals:
#   PG_CONFIG, MACHINE_HOME
# Arguments:
#   None
# Returns:
#   None
#######################################
function pg_config_init() {
  local restart_needed=false
  OP_START_TIME=$(date +%s)
  if ([[ ! -z ${PG_CONFIG+x} ]] && [[ "$PG_CONFIG" != "" ]]); then
    msg "Initializing Postgres config (postgresql.conf)..."
    PG_CONFIG_FILENAME=$(basename $PG_CONFIG)
    docker_exec bash -c "cat $MACHINE_HOME/$PG_CONFIG_FILENAME >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    restart_needed=true
  fi
  if [[ ! -z ${PG_CONFIG_AUTO+x} ]]; then
    msg "Auto-tuning PostgreSQL (mode: '$PG_CONFIG_AUTO')..."
    # TODO(NikolayS): better auto-tuning, more params
    # see:
    #    - https://pgtune.leopard.in.ua
    #    - https://postgresqlco.nf/ and https://github.com/jberkus/annotated.conf
    #    - http://pgconfigurator.cybertec.at/
    # TODO(NikolayS): use bc instead of python (add bc to the docker image first)
    local shared_buffers="$(echo "print round($RAM_MB / 4)" | python | awk -F '.' '{print $1}')MB"
    local effective_cache_size="$(echo "print round(3 * $RAM_MB / 4)" | python | awk -F '.' '{print $1}')MB"
    if [[ "$PG_CONFIG_AUTO" = "oltp" ]]; then
      local work_mem="$(echo "print round($RAM_MB / 5)" | python | awk -F '.' '{print $1}')kB"
    elif [[ "$PG_CONFIG_AUTO" = "olap" ]]; then
      local work_mem="$(echo "print round($RAM_MB / 5)" | python | awk -F '.' '{print $1}')kB"
    else
      err "ERROR: (ASSERT) must not reach this point."
      exit 1
    fi
    if [[ $work_mem = "0kB" ]]; then # sanity check, set to tiny value just to start
      work_mem="1kB"
    fi
    if [[ $DISK_ROTATIONAL = false ]]; then
      local random_page_cost="1.1"
      local effective_io_concurrency="200"
    else
      local random_page_cost="4.0"
      local effective_io_concurrency="2"
    fi
    if [[ $CPU_CNT > 1 ]]; then # Only for postgres 9.6+!
      local max_worker_processes="$CPU_CNT"
      local max_parallel_workers_per_gather="$(echo "print round($CPU_CNT / 2)" | python | awk -F '.' '{print $1}')"
      if [[ ! "$PG_VERSION" = "9.6" ]]; then # the following is only for 10+ (and we don't support 9.5 and older)
        local max_parallel_workers="$CPU_CNT"
      fi
    fi

    docker_exec bash -c "echo '# AUTO-TUNED KNOBS:' >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    docker_exec bash -c "echo 'shared_buffers = $shared_buffers' >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    docker_exec bash -c "echo 'effective_cache_size = $effective_cache_size' >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    docker_exec bash -c "echo 'work_mem = $work_mem' >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    docker_exec bash -c "echo 'random_page_cost = $random_page_cost' >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    docker_exec bash -c "echo 'effective_io_concurrency = $effective_io_concurrency' >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    docker_exec bash -c "echo 'max_worker_processes = $max_worker_processes' >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    docker_exec bash -c "echo 'max_parallel_workers_per_gather = $max_parallel_workers_per_gather' >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    if [[ ! "$PG_VERSION" = "9.6" ]]; then # the following is only for 10+ (and we don't support 9.5 and older)
      docker_exec bash -c "echo 'max_parallel_workers = $max_parallel_workers' >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    fi
    restart_needed=true
  fi
  if [[ ! -z ${DELTA_CONFIG+x} ]]; then # if DELTA_CONFIG is not empty, restart will be done later
    local restart_needed=false
  fi
  if [[ $restart_needed == true ]]; then
    stop_postgres
    start_postgres
  fi
  END_TIME=$(date +%s)
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Time taken to apply Postgres initial configuration: $DURATION."
}

#######################################
# Apply Postgres "delta" configuration
# Globals:
#   DELTA_CONFIG, MACHINE_HOME
# Arguments:
#   1 - path to file with delta config
# Returns:
#   None
#######################################
function apply_postgres_configuration() {
  local delta_config=$1
  # Apply postgres configuration
  OP_START_TIME=$(date +%s);
  if ([[ ! -z "$delta_config" ]] && [[ "$delta_config" != "" ]]); then
    msg "Apply postgres configuration"
    delta_config_filename=$(basename $delta_config)
    docker_exec bash -c "echo '# DELTA:' >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    docker_exec bash -c "cat $MACHINE_HOME/$delta_config_filename >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    stop_postgres
    start_postgres
    END_TIME=$(date +%s);
    DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
    msg "Time taken to apply Postgres configuration delta: $DURATION."
  fi
}

#######################################
# Prepare to start workload.
# Save restore db log, vacuumdb, clear log
# Globals:
#   ARTIFACTS_DIRNAME, MACHINE_HOME, DB_NAME, CURRENT_LSN_FUNCTION
# Arguments:
#   $1 - run number
# Returns:
#   None
#######################################
function prepare_start_workload() {
  local run_number=$1
  let run_number=run_number+1
  if [[ -z ${WORKLOAD_PGBENCH+x} ]]; then
    msg "Executing vacuumdb..."
    out=$(docker_exec vacuumdb -U postgres $DB_NAME -j $CPU_CNT --analyze)
  fi

  if [[ "$run_number" -eq "1" ]]; then
    msg "Save prepaparation log"
    docker_exec bash -c "gzip -c $LOG_PATH > $MACHINE_HOME/$ARTIFACTS_DIRNAME/postgresql.prepare.log.gz"
  fi

  dbg "Resetting pg_stat_*** and Postgres log and remembering current LSN..."
  (docker_exec psql -U postgres $DB_NAME -f - <<EOF
    select pg_stat_reset(), pg_stat_statements_reset(), pg_stat_kcache_reset(), pg_stat_reset_shared('archiver'), pg_stat_reset_shared('bgwriter');
    drop table if exists pg_stat_nancy_lsn;
    create table pg_stat_nancy_lsn as select now() as created_at, ${CURRENT_LSN_FUNCTION} as lsn;
EOF
) > /dev/null
  docker_exec bash -c "echo '' > $LOG_PATH"
}

#######################################
# Execute CPU test.
# Globals:
#   ARTIFACTS_DIRNAME, MACHINE_HOME, DB_NAME
# Arguments:
#   $1 - run number
# Returns:
#   None
#######################################
function do_cpu_test() {
  local run_number=$1
  let run_number=run_number+1
  dbg "Start CPU test"
  docker_exec bash -c "sysbench --test=cpu --num-threads=${CPU_CNT} --max-time=10 run 2>&1 | awk '{print \"$MSG_PREFIX\" \$0}' | tee $MACHINE_HOME/$ARTIFACTS_DIRNAME/sysbench_cpu_run.$run_number.txt $VERBOSE_OUTPUT_REDIRECT"
}

#######################################
# Execture file system test
# Globals:
#   ARTIFACTS_DIRNAME, MACHINE_HOME, DB_NAME
# Arguments:
#   $1 - run number
# Returns:
#   None
#######################################
function do_fs_test() {
  local run_number=$1
  let run_number=run_number+1
  dbg "Start FS test"
  docker_exec bash -c "mkdir -p /storage/fs_test"
  docker_exec bash -c "cd /storage/fs_test && sysbench --test=fileio --file-test-mode=rndrw --num-threads=${CPU_CNT} prepare 2>&1 | awk '{print \"$MSG_PREFIX\" \$0}' | tee $MACHINE_HOME/$ARTIFACTS_DIRNAME/sysbench_fs_prepare.$run_number.txt $VERBOSE_OUTPUT_REDIRECT"
  docker_exec bash -c "cd /storage/fs_test && sysbench --test=fileio --file-test-mode=rndrw --num-threads=${CPU_CNT} --max-time=10 run 2>&1 | awk '{print \"$MSG_PREFIX\" \$0}' | tee $MACHINE_HOME/$ARTIFACTS_DIRNAME/sysbench_fs_run.$run_number.txt $VERBOSE_OUTPUT_REDIRECT"
  docker_exec bash -c "rm /storage/fs_test/*"
}


#######################################
# Execute workload.
# Globals:
#   WORKLOAD_REAL, WORKLOAD_REAL_REPLAY_SPEED, WORKLOAD_CUSTOM_SQL, MACHINE_HOME,
#   DURATION_WRKLD, DB_NAME, VERBOSE_OUTPUT_REDIRECT
# Arguments:
#   $1 - run number
# Returns:
#   None
#######################################
function execute_workload() {
  local run_number=$1
  local verbose_output=""
  let run_number=run_number+1
  if $NO_OUTPUT; then
    verbose_output=$VERBOSE_OUTPUT_REDIRECT
  fi
  # Execute workload
  local verbose_output=""
  if $NO_OUTPUT; then
    verbose_output=$VERBOSE_OUTPUT_REDIRECT
  fi
  OP_START_TIME=$(date +%s)
  print_connection
  if [[ "${RUN_ON}" == "aws" ]]; then
    msg "Clear OS cache"
    docker_exec bash -c "sync; echo 3 > /proc/sys/vm/drop_caches"
  fi
  msg "Executing workload..."
  if [[ ! -z ${WORKLOAD_PGBENCH+x} ]]; then
      docker_exec bash -c "pgbench $WORKLOAD_PGBENCH -U postgres $DB_NAME 2>&1 | awk '{print \"$MSG_PREFIX\"\$0}' | tee $MACHINE_HOME/$ARTIFACTS_DIRNAME/workload_output.$run_number.txt $verbose_output"
  fi
  if [[ ! -z ${WORKLOAD_REAL+x} ]] && [[ "$WORKLOAD_REAL" != '' ]]; then
    msg "Executing pgreplay queries..."
    (docker_exec psql -U postgres $DB_NAME -f - <<EOF
    do
    \$do\$
    begin
       if not exists (select 1 from pg_catalog.pg_roles where rolname = 'testuser') then
          create role testuser superuser login;
       end if;
    end
    \$do\$;
EOF
) > /dev/null

    WORKLOAD_FILE_NAME=$(basename $WORKLOAD_REAL)
    if [[ ! -z ${WORKLOAD_REAL_REPLAY_SPEED+x} ]] && [[ "$WORKLOAD_REAL_REPLAY_SPEED" != '' ]]; then
      docker_exec bash -c "pgreplay -r -s $WORKLOAD_REAL_REPLAY_SPEED $MACHINE_HOME/$WORKLOAD_FILE_NAME 2>&1 \
      | awk '{print \"$MSG_PREFIX\"\$0}' | tee $MACHINE_HOME/$ARTIFACTS_DIRNAME/workload_output.$run_number.txt $verbose_output"
    else
      docker_exec bash -c "pgreplay -r -j $MACHINE_HOME/$WORKLOAD_FILE_NAME 2>&1 \
      | awk '{print \"$MSG_PREFIX\"\$0}' | tee $MACHINE_HOME/$ARTIFACTS_DIRNAME/workload_output.$run_number.txt $verbose_output"
    fi
  fi
  if ([ ! -z ${WORKLOAD_CUSTOM_SQL+x} ] && [ "$WORKLOAD_CUSTOM_SQL" != "" ]); then
    WORKLOAD_CUSTOM_FILENAME=$(basename $WORKLOAD_CUSTOM_SQL)
    msg "Executing custom SQL queries..."
    docker_exec bash -c "psql -U postgres $DB_NAME -E -f $MACHINE_HOME/$WORKLOAD_CUSTOM_FILENAME $verbose_output"
  fi
  END_TIME=$(date +%s)
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Time taken to execute workload: $DURATION."
  DURATION_WRKLD="$DURATION"
}

#######################################
# Save artifacts to artifact destination
# Globals:
#   CONTAINER_HASH, MACHINE_HOME, ARTIFACTS_DESTINATION, ARTIFACTS_DIRNAME
# Arguments:
#   None
# Returns:
#   None
#######################################
function save_artifacts() {
  msg "Saving artifacts..."
  local out

  copy_file "${TMP_PATH}/system_info.txt"
  copy_file "${TMP_PATH}/nancy_start_params.txt"
  docker_exec bash -c "cp $MACHINE_HOME/system_info.txt $MACHINE_HOME/$ARTIFACTS_DIRNAME/"
  docker_exec bash -c "cp $MACHINE_HOME/nancy_start_params.txt $MACHINE_HOME/$ARTIFACTS_DIRNAME/"

  if [[ $ARTIFACTS_DESTINATION =~ "s3://" ]]; then
    out=$(docker_exec s3cmd --recursive put /$MACHINE_HOME/$ARTIFACTS_DIRNAME $ARTIFACTS_DESTINATION/ 2>&1)
  else
    if [[ "$RUN_ON" == "localhost" ]]; then
      out=$(docker cp $CONTAINER_HASH:$MACHINE_HOME/$ARTIFACTS_DIRNAME $ARTIFACTS_DESTINATION/ 2>&1)
    elif [[ "$RUN_ON" == "aws" ]]; then
      mkdir -p $ARTIFACTS_DESTINATION/$ARTIFACTS_DIRNAME
      #out=$(docker-machine scp $DOCKER_MACHINE:/home/storage/$ARTIFACTS_DIRNAME/* $ARTIFACTS_DESTINATION/$ARTIFACTS_DIRNAME/)
      out=$(docker-machine scp $DOCKER_MACHINE:/home/ubuntu/$ARTIFACTS_DIRNAME/* $ARTIFACTS_DESTINATION/$ARTIFACTS_DIRNAME/)
    else
      err "ERROR: (ASSERT) must not reach this point."
      exit 1
    fi
  fi

  # save summary as artifact
  local cur_sum_fname=""
  for cur_sum_fname in "$TMP_PATH"/summary.*.txt; do
    [[ -e "${cur_sum_fname}" ]] || continue
    cp "${cur_sum_fname}" "$ARTIFACTS_DESTINATION/$ARTIFACTS_DIRNAME/"
  done

  msg "Artifacts saved"
}

#######################################
# Collect results of workload execution
# Globals:
#   CONTAINER_HASH, MACHINE_HOME, ARTIFACTS_DESTINATION, PG_STAT_TOTAL_TIME,
#   CURRENT_LSN_FUNCTION
# Arguments:
#   $1 - run number
# Returns:
#   None
#######################################
function collect_results() {
  local run_number=$1
  let run_number=run_number+1
  ## Get statistics
  OP_START_TIME=$(date +%s)
  if [[ -z ${NO_PGBADGER+x} ]]; then
    for report_type in "json" "html"; do
      msg "Generating $report_type report..."
      docker_exec bash -c "/root/pgbadger/pgbadger \
        -j $CPU_CNT \
        --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' /var/log/postgresql/* -f stderr \
        -o $MACHINE_HOME/$ARTIFACTS_DIRNAME/pgbadger.$run_number.$report_type $VERBOSE_OUTPUT_REDIRECT" \
        2> >(grep -v "install the Text::CSV_XS" >&2)
    done
  fi

  out=$(docker_exec psql -U postgres $DB_NAME -c "select sum(total_time) from pg_stat_statements where query not like 'copy%' and query not like '%reset%';")
  PG_STAT_TOTAL_TIME=${out//[!0-9.]/}

  for table2export in \
    "pg_settings order by name" \
    "pg_stat_statements order by total_time desc" \
    "pg_stat_kcache() order by reads desc" \
    "pg_stat_archiver" \
    "pg_stat_bgwriter" \
    "pg_stat_database order by datname" \
    "pg_stat_database_conflicts order by datname" \
    "pg_stat_all_tables order by schemaname, relname" \
    "pg_stat_xact_all_tables order by schemaname, relname" \
    "pg_stat_all_indexes order by schemaname, relname, indexrelname" \
    "pg_statio_all_tables order by schemaname, relname" \
    "pg_statio_all_indexes order by schemaname, relname, indexrelname" \
    "pg_statio_all_sequences order by schemaname, relname" \
    "pg_stat_user_functions order by schemaname, funcname" \
    "pg_stat_xact_user_functions order by schemaname, funcname" \
  ; do
    docker_exec bash -c "psql -U postgres $DB_NAME -b -c \"copy (select * from $table2export) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_DIRNAME/\$(echo \"$table2export\" | awk '{print \$1}').$run_number.csv"
  done

  docker_exec bash -c "
    psql -U postgres $DB_NAME -b -c \"
      copy (
        select
          ${CURRENT_LSN_FUNCTION} - lsn as wal_bytes_generated,
          pg_size_pretty(${CURRENT_LSN_FUNCTION} - lsn) wal_pretty_generated,
          pg_size_pretty(3600 * round(((${CURRENT_LSN_FUNCTION} - lsn) / extract(epoch from now() - created_at))::numeric, 2)) || '/h' as wal_avg_per_h
        from pg_stat_nancy_lsn
      ) to stdout with csv header delimiter ',';\" > /$MACHINE_HOME/$ARTIFACTS_DIRNAME/wal_stats.${run_number}.csv
  "

  docker_exec bash -c "gzip -c $LOG_PATH > $MACHINE_HOME/$ARTIFACTS_DIRNAME/postgresql.workload.$run_number.log.gz"
  docker_exec bash -c "cp /etc/postgresql/$PG_VERSION/main/postgresql.conf $MACHINE_HOME/$ARTIFACTS_DIRNAME/postgresql.$run_number.conf"

  END_TIME=$(date +%s)
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Time taken to generate and collect artifacts: $DURATION."
}

#######################################
# Collect artifacts in case of abnormal termination
# Globals:
#   MACHINE_HOME
# Arguments:
#   None
# Returns:
#   None
#######################################
function docker_cleanup_and_exit {
  if [[ -z "${DONE+x}" ]]; then
    docker_exec bash -c "mkdir -p $MACHINE_HOME/$ARTIFACTS_DIRNAME"
    docker_exec bash -c "gzip -c $LOG_PATH > $MACHINE_HOME/$ARTIFACTS_DIRNAME/postgresql.abnormal.log.gz"
    err "Abnormal termination. Check artifacts to understand the reasons."
    save_artifacts
    calc_estimated_cost
  fi
  cleanup_and_exit
}

#######################################
# Run perf in background
# Globals:
#   MACHINE_HOME
# Arguments:
#   $1 - run number
# Returns:
#   (integer) ret_code
#######################################
function start_perf {
  local run_number=$1
  let run_number=run_number+1
  set +e
  local ret_code="0"

  if [[ ! -z ${NO_PERF+x} ]]; then
    return 0
  fi

  msg "Run perf in background."
  docker_exec bash -c "cd /root/FlameGraph/ \
    && (nohup perf record -F 99 -a -g -o perf.${run_number}.data >/dev/null 2>&1 </dev/null & \
    echo \$! > /tmp/perf_pid)"
  ret_code="$?"
  set -e
  return "$ret_code"
}

#######################################
# Stop perf and generate FlameGraph artifacts
# Globals:
#   ARTIFACTS_DIRNAME
# Arguments:
#   $1 - run number
# Returns:
#   (integer) ret_code
#######################################
function stop_perf {
  local run_number=$1
  let run_number=run_number+1
  set +e
  local ret_code="0"

  if [[ ! -z ${NO_PERF+x} ]]; then
    return 0
  fi

  msg "Stopping perf..."
  docker_exec bash -c "test -f /tmp/perf_pid \
    && while kill \$(cat /tmp/perf_pid) 2>/dev/null; do sleep 1; done" \
    && dbg "perf should be stopped."

  msg "Generating FlameGraph..."
  docker_exec bash -c "cd /root/FlameGraph \
    && perf script --input perf.${run_number}.data 2>${STDERR_DST} \
    | ./stackcollapse-perf.pl > out.${run_number}.perf-folded 2>${STDERR_DST} \
    && ./flamegraph.pl out.${run_number}.perf-folded > perf-kernel.${run_number}.svg 2>${STDERR_DST} \
    && cp perf-kernel.${run_number}.svg ${MACHINE_HOME}/${ARTIFACTS_DIRNAME}/"
  ret_code="$?"
  set -e
  return "$ret_code"
}

#######################################
# Start log monitoring: mpstat, iostat, etc.
# in the background.
# Globals:
#   ARTIFACTS_DIRNAME, MACHINE_HOME
# Arguments:
#   $1 - run number
# Returns:
#   None
#######################################
function start_monitoring {
  local run_number=$1
  let run_number=run_number+1
  # WARNING: do not forget stop logging at stop_monitoring() function
  local freq="10" # every 10 sec (frequency)
  local ret_code=0
  set +e
  msg "Start monitoring."

  # mpstat cpu
  docker_exec bash -c "nohup bash -c \"set -ueo pipefail; \
    mpstat -P ALL ${freq} 2>&1 | ts \
    | tee ${MACHINE_HOME}/${ARTIFACTS_DIRNAME}/mpstat.${run_number}.log\" \
     >/dev/null 2>&1 </dev/null &"
  ret_code="$?"
  [[ "$ret_code" -ne "0" ]] && err "WARNING: Can't execute mpstat"

  # iostat
  docker_exec bash -c "nohup bash -c \"set -ueo pipefail; \
    LC_ALL=en_US.UTF-8 iostat -ymxt ${freq} \
    | tee ${MACHINE_HOME}/${ARTIFACTS_DIRNAME}/iostat.${run_number}.log\" \
     >/dev/null 2>&1 </dev/null &"
  ret_code="$?"
  [[ "$ret_code" -ne "0" ]] && err "WARNING: Can't execute iostat"

  # meminfo
  docker_exec bash -c "nohup bash -c \"export FREQ=${freq} && [[ -f ${MACHINE_HOME}/meminfo.sh ]] && ${MACHINE_HOME}/meminfo.sh\" >/dev/null 2>&1 </dev/null &"
  ret_code="$?"
  [[ "$ret_code" -ne "0" ]] && err "WARNING: Can't execute iostat"

  set -e
}

#######################################
# Stop monitoring (we need it for series runs)
# Globals:
#   ARTIFACTS_DIRNAME, MACHINE_HOME
# Arguments:
#   $1 - run number
# Returns:
#   None
#######################################
function stop_monitoring {
  local run_number=$1
  let run_number=run_number+1
  set +e
  # mpstat cpu
  msg "Stop monitoring."
  docker_exec bash -c "killall mpstat >/dev/null 2>&1"
  cpu_num=0
  docker_exec bash -c "echo 'time;cpu_num;%usr;%nice;%iowait;%steal' > ${MACHINE_HOME}/${ARTIFACTS_DIRNAME}/mpstat.${run_number}.csv"
  while [[ $cpu_num -lt $CPU_CNT ]]; do
    docker_exec bash -c "cat ${MACHINE_HOME}/${ARTIFACTS_DIRNAME}/mpstat.${run_number}.log | grep -P '^... \d\d \d\d:\d\d:\d\d \d\d:\d\d:\d\d +${cpu_num}' | awk '{print \$1\" \"\$2\" \"\$4\";\"\$5\";\"\$6\";\"\$7\";\"\$9\";\"\$12}' >> ${MACHINE_HOME}/${ARTIFACTS_DIRNAME}/mpstat.${run_number}.csv"
    let cpu_num=$cpu_num+1
  done
  # iostat
  docker_exec bash -c "killall iostat >/dev/null 2>&1"
  # meminfo
  docker_exec bash -c "killall meminfo.sh"
  docker_exec bash -c "[[ -f /machine_home/meminfo.run.log ]] && mv /machine_home/meminfo.run.log ${MACHINE_HOME}/${ARTIFACTS_DIRNAME}/meminfo.${run_number}.log"
  docker_exec bash -c "[[ -f /machine_home/meminfo.run.csv ]] && mv /machine_home/meminfo.run.csv ${MACHINE_HOME}/${ARTIFACTS_DIRNAME}/meminfo.${run_number}.csv"
  msg "Generating iostat graph..."
  docker_exec bash -c "cd ${MACHINE_HOME}/${ARTIFACTS_DIRNAME} && iostat-cli --data iostat.${run_number}.log plot $VERBOSE_OUTPUT_REDIRECT || true"
  docker_exec bash -c "mv ${MACHINE_HOME}/${ARTIFACTS_DIRNAME}/iostat.png ${MACHINE_HOME}/${ARTIFACTS_DIRNAME}/iostat.${run_number}.png $VERBOSE_OUTPUT_REDIRECT"
  set -e
}

#######################################
# Do rollback to earlier created ZFS snapshot with stop and start postgres
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function zfs_rollback_snapshot {
  OP_START_TIME=$(date +%s)
  dbg "Rollback database"
  stop_postgres
  docker_exec bash -c "zfs rollback -f -r zpool@init_db $VERBOSE_OUTPUT_REDIRECT"
  start_postgres
  END_TIME=$(date +%s)
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Time taken to rollback database: $DURATION."
}

#######################################
# Create ZFS snapshot with stop and start postgres
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function zfs_create_snapshot {
  OP_START_TIME=$(date +%s)
  dbg "Create database snapshot"
  stop_postgres
  docker_exec bash -c "zfs snapshot -r zpool@init_db  $VERBOSE_OUTPUT_REDIRECT"
  start_postgres
  END_TIME=$(date +%s)
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Time taken to create database snapshot: $DURATION."
}

#######################################
# Tune AWS Linux host for better performance
# Globals:
#   DOCKER_MACHINE
# Arguments:
#   None
# Returns:
#   None
#######################################
function tune_host_machine {
  if [[ "$RUN_ON" == "aws" ]]; then
    # Switch CPU to performance mode
    docker-machine ssh $DOCKER_MACHINE \
      "[[ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]] \
       && echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor || true"
    # Disable swap
    docker-machine ssh $DOCKER_MACHINE \
      "[[ -e /proc/sys/vm/swappiness ]] \
       && sudo bash -c 'echo 0 > /proc/sys/vm/swappiness' || true"
  fi
}

tune_host_machine
if [[ -f ${BASH_SOURCE%/*}/tools/meminfo.sh ]]; then
  copy_file ${BASH_SOURCE%/*}/tools/meminfo.sh
  docker_exec bash -c "chmod +x ${MACHINE_HOME}/meminfo.sh"
fi

trap docker_cleanup_and_exit EXIT

if [[ ! -z ${DB_EBS_VOLUME_ID+x} ]] && [[ ! "$DB_NAME" == "test" ]]; then
  docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres -c 'drop database if exists test;'"
  docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres -c 'alter database $DB_NAME rename to test;'"
  ORIGINAL_DB_NAME=$DB_NAME
  DB_NAME=test
fi

[ ! -z ${S3_CFG_PATH+x} ] && copy_file $S3_CFG_PATH \
  && docker_exec cp $MACHINE_HOME/.s3cfg /root/.s3cfg
[ ! -z ${DB_DUMP+x} ] && copy_file $DB_DUMP
[ ! -z ${PG_CONFIG+x} ] && copy_file $PG_CONFIG
[ ! -z ${WORKLOAD_CUSTOM_SQL+x} ] && copy_file $WORKLOAD_CUSTOM_SQL
[ ! -z ${WORKLOAD_REAL+x} ] && copy_file $WORKLOAD_REAL

runs_count=${#RUNS[*]}
let runs_count=runs_count/3
i=0
while : ; do
  j=$i*3
  d=$j+1
  u=$j+2
  delta_config=${RUNS[$j]}
  delta_ddl_do=${RUNS[$d]}
  delta_ddl_undo=${RUNS[$u]}
  [[ ! -z "$delta_config" ]] && copy_file $delta_config
  [[ ! -z "$delta_ddl_do" ]] && copy_file $delta_ddl_do
  [[ ! -z "$delta_ddl_undo" ]] && copy_file $delta_ddl_undo
  let i=$i+1
  [[ "$i" -eq "$runs_count" ]] && break;
done

## Apply machine features
# Dump
sleep 10 # wait for postgres up&running

docker_exec bash -c "psql -U postgres $DB_NAME -b -c 'create extension if not exists pg_stat_statements;' $VERBOSE_OUTPUT_REDIRECT"
docker_exec bash -c "psql -U postgres $DB_NAME -b -c 'create extension if not exists pg_stat_kcache;' $VERBOSE_OUTPUT_REDIRECT"

apply_commands_after_container_init
pg_config_init
apply_sql_before_db_restore
if [[ ! -z ${DB_DUMP+x} ]] || [[ ! -z ${DB_PGBENCH+x} ]]; then
  restore_dump
fi
apply_sql_after_db_restore

if [[ "${RUN_ON}" == "aws" ]]; then
  docker_exec bash -c "mkdir /machine_home/$ARTIFACTS_DIRNAME"
  docker_exec bash -c "ln -s /machine_home/$ARTIFACTS_DIRNAME $MACHINE_HOME/$ARTIFACTS_DIRNAME"
else
  docker_exec bash -c "mkdir $MACHINE_HOME/$ARTIFACTS_DIRNAME"
fi

if [[ ! -z ${AWS_ZFS+x} ]]; then
  zfs_create_snapshot
fi

runs_count=${#RUNS[*]}
let runs_count=runs_count/3
i=0
while : ; do
  j=$i*3
  d=$j+1
  u=$j+2
  let num=$i+1
  msg "Experimental run (sequential number): #$num."
  delta_config=${RUNS[$j]}
  delta_ddl_do=${RUNS[$d]}
  delta_ddl_undo=${RUNS[$u]}

  if [[ "$runs_count" -gt "1" ]] && [[ ! -z "$delta_config" ]]; then
    MSG_PREFIX=$(cat $delta_config | tail -n 1)
    MSG_PREFIX="$MSG_PREFIX > "
  else
    MSG_PREFIX=""
  fi

  do_cpu_test $i
  do_fs_test $i

  summary_fname="${TMP_PATH}/summary.${num}.txt"

  #restore database if not first run
  if [[ "$i" -gt "0" ]]; then
    sleep 10
    if [[ ! -z ${AWS_ZFS+x} ]]; then
      zfs_rollback_snapshot
    elif [[ ! -z ${DB_EBS_VOLUME_ID+x} ]]; then
      stop_postgres
      rsync_backup
      start_postgres
    else
      restore_dump;
    fi
    sleep 10
  fi

  # apply delta
  [[ ! -z "$delta_config" ]] && apply_postgres_configuration $delta_config
  [[ ! -z "$delta_ddl_do" ]] && apply_ddl_do_code $delta_ddl_do

  prepare_start_workload $i
  start_perf $i || true
  start_monitoring $i
  execute_workload $i
  stop_perf $i || true
  stop_monitoring $i
  collect_results $i

  echo "Run #$num done."
  # start printing summary
  if ([[ ! -z "$delta_config" ]] || [[ ! -z "$delta_ddl_do" ]]); then
    echo -e "------------------------------------------------------------------------------" | tee -a "$summary_fname"
    if [[ ! -z "$delta_config" ]]; then
      echo -e "Config delta:         $delta_config" | tee -a "$summary_fname"
    fi
    if [[ ! -z "$delta_ddl_do" ]]; then
      echo -e "DDL delta:            $delta_ddl_do" | tee -a "$summary_fname"
    fi
  fi
  echo -e "------------------------------------------------------------------------------" | tee -a "$summary_fname"
  echo -e "${MSG_PREFIX}Artifacts (collected in \"$ARTIFACTS_DESTINATION/$ARTIFACTS_DIRNAME/\"):" | tee -a "$summary_fname"
  echo -e "${MSG_PREFIX}  Postgres config:    postgresql.$num.conf" | tee -a "$summary_fname"
  if [[ "$runs_count" -eq "1" ]]; then
    echo -e "${MSG_PREFIX}  Postgres logs:      postgresql.prepare.log.gz (preparation)," | tee -a "$summary_fname"
  fi
  echo -e "                      postgresql.workload.$num.log.gz (workload)" | tee -a "$summary_fname"
  if [[ -z ${NO_PGBADGER+x} ]]; then
    echo -e "${MSG_PREFIX}  pgBadger reports:   pgbadger.$num.html (for humans)," | tee -a "$summary_fname"
    echo -e "                      pgbadger.$num.json (for robots)" | tee -a "$summary_fname"
  fi
  echo -e "${MSG_PREFIX}  Stat stapshots:     pg_stat_statements.$num.csv," | tee -a "$summary_fname"
  echo -e "                      pg_stat_***.$num.csv" | tee -a "$summary_fname"
  echo -e "------------------------------------------------------------------------------" | tee -a "$summary_fname"
  echo -e "${MSG_PREFIX}Total execution time: $DURATION" | tee -a "$summary_fname"
  echo -e "------------------------------------------------------------------------------" | tee -a "$summary_fname"
  echo -e "${MSG_PREFIX}Workload:" | tee -a "$summary_fname"
  echo -e "${MSG_PREFIX}  Execution time:     $DURATION_WRKLD" | tee -a "$summary_fname"
  if [[ -z ${NO_PGBADGER+x} ]]; then
    echo -e "${MSG_PREFIX}  Total query time:   "$(docker_exec cat $MACHINE_HOME/$ARTIFACTS_DIRNAME/pgbadger.$num.json | jq '.overall_stat.queries_duration') " ms" | tee -a "$summary_fname"
    echo -e "${MSG_PREFIX}  Queries:            "$(docker_exec cat $MACHINE_HOME/$ARTIFACTS_DIRNAME/pgbadger.$num.json | jq '.overall_stat.queries_number') | tee -a "$summary_fname"
    echo -e "${MSG_PREFIX}  Query groups:       "$(docker_exec cat $MACHINE_HOME/$ARTIFACTS_DIRNAME/pgbadger.$num.json | jq '.normalyzed_info | length') | tee -a "$summary_fname"
    echo -e "${MSG_PREFIX}  Errors:             "$(docker_exec cat $MACHINE_HOME/$ARTIFACTS_DIRNAME/pgbadger.$num.json | jq '.overall_stat.errors_number') | tee -a "$summary_fname"
    echo -e "${MSG_PREFIX}  Errors groups:      "$(docker_exec cat $MACHINE_HOME/$ARTIFACTS_DIRNAME/pgbadger.$num.json | jq '.error_info | length') | tee -a "$summary_fname"
  else
    if [[ ! -z ${PG_STAT_TOTAL_TIME+x} ]]; then
      echo -e "${MSG_PREFIX}  Total query time:   $PG_STAT_TOTAL_TIME ms" | tee -a "$summary_fname"
    fi
  fi

  if [[ ! -z ${WORKLOAD_PGBENCH+x} ]]; then
    tps_string=$(docker_exec cat $MACHINE_HOME/$ARTIFACTS_DIRNAME/workload_output.$num.txt | grep "including connections establishing")
    tps=${tps_string//[!0-9.]/}
    if [[ ! -z "$tps" ]]; then
      echo -e "${MSG_PREFIX}  TPS:                $tps (including connections establishing)" | tee -a "$summary_fname"
    fi
  fi

  if [[ ! -z ${WORKLOAD_REAL+x} ]]; then
    avg_num_con_string=$(docker_exec cat $MACHINE_HOME/$ARTIFACTS_DIRNAME/workload_output.$num.txt | grep "Average number of concurrent connections")
    avg_num_con=${avg_num_con_string//[!0-9.]/}
    if [[ ! -z "$avg_num_con" ]]; then
      echo -e "${MSG_PREFIX}  Avg. connection number: $avg_num_con" | tee -a "$summary_fname"
    fi
  fi

  echo -e "${MSG_PREFIX}  WAL:                $(docker_exec tail -1 $MACHINE_HOME/$ARTIFACTS_DIRNAME/wal_stats.$num.csv | awk -F',' '{print $1" bytes generated ("$2"), avg tput: "$3}')" | tee -a "$summary_fname"
  checkpoint_data=$(docker_exec tail -1 $MACHINE_HOME/$ARTIFACTS_DIRNAME/pg_stat_bgwriter.$num.csv)
  echo -e "${MSG_PREFIX}  Checkpoints:        $(echo $checkpoint_data | awk -F',' '{print $1}') planned (timed)" | tee -a "$summary_fname"
  echo -e "${MSG_PREFIX}                      $(echo $checkpoint_data | awk -F',' '{print $2}') forced (requested)" | tee -a "$summary_fname"
  checkpoint_buffers=$(echo $checkpoint_data | awk -F',' '{print $5}')
  checkpoint_write_t=$(echo $checkpoint_data | awk -F',' '{print $3}')
  checkpoint_sync_t=$(echo $checkpoint_data | awk -F',' '{print $4}')
  checkpoint_t=$(( checkpoint_write_t + checkpoint_sync_t ))
  checkpoint_mb=$(( checkpoint_buffers * 8 / 1024 ))

  if [[ $checkpoint_t > 0 ]]; then
    checkpoint_mbps=$(( checkpoint_buffers * 8000 / (1024 * checkpoint_t) ))
  else
    checkpoint_mbps=0
  fi
  echo -e "${MSG_PREFIX}                      ${checkpoint_buffers} buffers (${checkpoint_mb} MiB), took ${checkpoint_t} ms, avg tput: ${checkpoint_mbps} MiB/s" | tee -a "$summary_fname"

  echo -e "------------------------------------------------------------------------------" | tee -a "$summary_fname"
  # end of summary

  # revert delta
  [[ ! -z "$delta_ddl_undo" ]] && apply_ddl_undo_code $delta_ddl_undo
  let i=$i+1
  [[ "$i" -eq "$runs_count" ]] && break;
done

save_artifacts
calc_estimated_cost
DONE=1
