volume#!/bin/bash

KB=1024
DEBUG=0
CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
DOCKER_MACHINE="nancy-$CURRENT_TS"
DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
DEBUG_TIMEOUT=0
OUTPUT_REDIRECT=" > /dev/null"
EBS_SIZE_MULTIPLIER=15

function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $@" >&2
}

function msg() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $@"
}

## Get command line params
while true; do
  case "$1" in
    help )
        echo -e "\033[1mCOMMAND\033[22m

    run

\033[1mDESCRIPTION\033[22m

  Nancy is a member of Postgres.ai's Artificial DBA team responsible for
  conducting experiments.

  Use 'nancy run' to request a new run for some experiment being conducted.

  An experiment consists of one or more 'runs'. For instance, if Nancy is being
  used to verify  that a new index  will affect  performance only in a positive
  way, two runs are needed. If one needs to only  collect  query plans for each
  query group, a single run is enough. And finally, if there is  a goal to find
  an optimal value for some PostgreSQL setting, multiple runs will be needed to
  check how various values of the specified setting affect performance of the
  specified database and workload.

  4 main parts of each run are:
    - environment: where it will happen, PostgreSQL version, etc;
    - database: copy or clone of some database;
    - workload: 'real' workload or custom SQL;
    - target: PostgreSQL config changes or some DDL such as 'CREATE INDEX ...'.

\033[1mOPTIONS\033[22m

  NOTICE: A value for a string option that starts with 'file://' is treated as
          a path to a local file. A string value starting with 's3://' is
          treated as a path to remote file located in S3 (AWS S3 or analog).
          Otherwise, a string values is considered as 'content', not a link to
          a file.

  \033[1m--debug\033[22m (boolean)

  Turn on debug logging.

  \033[1m--debug-timeout\033[22m (string)

  How many seconds the entity (Docker container, Docker machine) where
  experimental run is being made will be alive after the main activity is
  finished. This is useful for various debugging: one can access container via
  ssh / docker exec and see PostgreSQL with data, logs, etc.

  \033[1m--run-on\033[22m (string)

  Specify, where the experimental run will take place

    * 'localhost' (default)

    * aws

    * gcp (WIP)

  If 'localhost' is specified (or --run-on is omitted), Nancy will perform the
  run on the localhost in a Docker container so ('docker run' must work
  locally).

  If 'aws' is specified, Nancy will use a Docker machine with a single
  container running on an EC2 Spot instance.

  \033[1m--pg-version\033[22m (string)

  Specify Major PostgreSQL version.

    * 9.6

    * 10 (default)

    * 11devel (WIP)

  \033[1m--pg-config\033[22m (string)

  Specify PostgreSQL config to be used (may be partial).

  \033[1m--db-prepared-snapshot\033[22m (string)

  Reserved / Not yet implemented.

  \033[1m--db-dump\033[22m (string)

  Specify the path to database dump (created by pg_dump) to be used as an input.

  \033[1m--sql-after-db-restore\033[22m (string)

  Specify additional commands to be executed after database is initiated (dump
  loaded or snapshot attached).

  \033[1m--workload-real\033[22m (string)

  Path to 'real' workload prepared by using 'nancy prepare-workload'.

  \033[1m--workload-basis\033[22m (string)

  Reserved / Not yet implemented.

  \033[1m--workload-custom-sql\033[22m (string)

  Specify custom SQL queries to be used as an input.

  \033[1m--workload-real-replay-speed\033[22m (string)

  Reserved / Not yet implemented.

  \033[1m--target-ddl-do\033[22m (string)

  SQL changing database somehow before workload is applied. 'Do DDL' example:

      create index i_t1_experiment on t1 using btree(col1);
      vacuum analyze t1;

  \033[1m--target-ddl-undo\033[22m (string)

  SQL reverting changes produced by those specified in the value of the
  '--target-ddl-do' option. Reverting allows to serialize multiple runs, but it
  might be not possible in some cases. 'Undo DDL' example:

      drop index i_t1_experiment;

  \033[1m--target-config\033[22m (string)

  Config changes to be applied to postgresql.conf before workload is applied.
  Once configuration changes are made, PostgreSQL is restarted. Example:

      random_page_cost = 1.1

  \033[1m--artifacts-destination\033[22m (string)

  Path to a local ('file://...') or S3 ('s3://...') directory where Nancy will
  put all collected results of the run, including:

  * detailed performance report in JSON format

  * whole PostgreSQL log, gzipped

  \033[1m--aws-ec2-type\033[22m (string)

  EC2 instance type where the run will be performed. An EC2 Spot instance will
  be used. WARNING: 'i3-metal' instances are not currently supported (WIP).

  The option may be used only with '--run-on aws'.

  \033[1m--aws-keypair-name\033[22m (string)

  The name of key pair used on EC2 instance to allow accessing to it. Must
  correspond to the value of the '--aws-ssh-key-path' option.

  The option may be used only with '--run-on aws'.

  \033[1m--aws-ssh-key-path\033[22m (string)

  Path to SSH key file (usually, has '.pem' extension).

  The option may be used only with '--run-on aws'.

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
      OUTPUT_REDIRECT='';
      shift ;;
    --run-on )
      RUN_ON="$2"; shift 2 ;;
    --container-id )
      CONTAINER_ID="$2"; shift 2 ;;
    --pg-version )
      PG_VERSION="$2"; shift 2 ;;
    --pg-config )
      #Still unsupported
      PG_CONFIG="$2"; shift 2;;
    --db-prepared-snapshot )
      #Still unsupported
      DB_PREPARED_SNAPSHOT="$2"; shift 2 ;;
    --db-dump )
      DB_DUMP_PATH="$2"; shift 2 ;;
    --commands-after-docker-init )
      AFTER_DOCKER_INIT_CODE="$2"; shift 2 ;;
    --sql-after-db-restore )
      #s3 url|filename|content
      AFTER_DB_INIT_CODE="$2"; shift 2 ;;
    --sql-before-db-restore )
      #s3 url|filename|content
      BEFORE_DB_INIT_CODE="$2"; shift 2 ;;
    --workload-real )
      #s3 url
      WORKLOAD_REAL="$2"; shift 2 ;;
    --workload-basis )
      #Still unsupported
      WORKLOAD_BASIS="$2"; shift 2 ;;
    --workload-custom-sql )
      #s3 url|filename|content
      WORKLOAD_CUSTOM_SQL="$2"; shift 2 ;;
    --workload-real-replay-speed )
      WORKLOAD_REAL_REPLAY_SPEED="$2"; shift 2 ;;
    --target-ddl-do )
      #s3 url|filename|content
      TARGET_DDL_DO="$2"; shift 2 ;;
    --target-ddl-undo )
      #s3 url|filename|content
      TARGET_DDL_UNDO="$2"; shift 2 ;;
    --target-config )
      #s3 url|filename|content
      TARGET_CONFIG="$2"; shift 2 ;;
    --artifacts-destination )
      ARTIFACTS_DESTINATION="$2"; shift 2 ;;
    --artifacts-filename )
      ARTIFACTS_FILENAME="$2"; shift 2 ;;

    --aws-ec2-type )
      AWS_EC2_TYPE="$2"; shift 2 ;;
    --aws-keypair-name )
      AWS_KEY_PAIR="$2"; shift 2 ;;
    --aws-ssh-key-path )
      AWS_KEY_PATH="$2"; shift 2 ;;

    --s3cfg-path )
      S3_CFG_PATH="$2"; shift 2 ;;
    --tmp-path )
      TMP_PATH="$2"; shift 2 ;;
    --debug-timeout )
      DEBUG_TIMEOUT="$2"; shift 2 ;;
    --ebs-volume-size )
        EBS_VOLUME_SIZE="$2"; shift 2 ;;
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

if [ $DEBUG -eq 1 ]; then
  echo "debug: ${DEBUG}"
  echo "debug timeout: ${DEBUG_TIMEOUT}"
  echo "run_on: ${RUN_ON}"
  echo "container_id: ${CONTAINER_ID}"
  echo "aws_ec2_type: ${AWS_EC2_TYPE}"
  echo "aws-key-pair: $AWS_KEY_PAIR"
  echo "aws-key-path: $AWS_KEY_PATH"
  echo "pg_version: ${PG_VERSION}"
  echo "pg_config: ${PG_CONFIG}"
  echo "db_prepared_snapshot: ${DB_PREPARED_SNAPSHOT}"
  echo "db_dump_path: $DB_DUMP_PATH"
  echo "workload_real: $WORKLOAD_REAL"
  echo "workload_basis: $WORKLOAD_BASIS"
  echo "workload_custom_sql: $WORKLOAD_CUSTOM_SQL"
  echo "workload_real_replay_speed: $WORKLOAD_REAL_REPLAY_SPEED"
  echo "target_ddl_do: $TARGET_DDL_DO"
  echo "target_ddl_undo: $TARGET_DDL_UNDO"
  echo "target_config: $TARGET_CONFIG"
  echo "artifacts_destination: $ARTIFACTS_DESTINATION"
  echo "s3-cfg-path: $S3_CFG_PATH"
  echo "tmp-path: $TMP_PATH"
  echo "after-db-init-code: $AFTER_DB_INIT_CODE"
  echo "after_docker_init_code: $AFTER_DOCKER_INIT_CODE"
  echo "before-db-init-code: $BEFORE_DB_INIT_CODE"
  echo "ebs-volume-size: $EBS_VOLUME_SIZE"
fi

function checkPath() {
  if [ -z $1 ]
  then
    return 1
  fi
  eval path=\$$1
  if [[ $path =~ "s3://" ]]
  then
    return 0; ## do not check
  fi
  if [[ $path =~ "file:///" ]]
  then
    path=${path/file:\/\//}
    if [ -f $path ]
    then
      eval "$1=\"$path\"" # update original variable
      return 0 # file found
    else
      return 2 # file not found
    fi
  fi
  if [[ $path =~ "file://" ]]
  then
    curdir=$(pwd)
    path=$curdir/${path/file:\/\//}
    if [ -f $path ]
    then
      eval "$1=\"$path\"" # update original variable
      return 0 # file found
    else
      return 2 # file not found
    fi
  fi
  return -1 # incorrect path
}

## Check params
function checkParams() {
  if [[ ("$RUN_ON" != "aws") && ("$RUN_ON" != "localhost") ]]; then
    err "ERROR: incorrect value for option --run-on"
    exit 1
  fi
  if [[ "$RUN_ON" == "aws" ]]; then
    if [ ! -z ${CONTAINER_ID+x} ]
    then
      err "ERROR: Container ID may be specified only for local runs."
      exit 1
    fi
    if [ -z ${AWS_KEY_PAIR+x} ] || [ -z ${AWS_KEY_PATH+x} ]
    then
      err "ERROR: AWS keys not given."
      exit 1
    else
      checkPath AWS_KEY_PATH
    fi

    if [ -z ${AWS_EC2_TYPE+x} ]
    then
      err "ERROR: AWS EC2 Instance type not given."
      exit 1
    fi
  elif [[ "$RUN_ON" == "localhost" ]]; then
    if [ ! -z ${AWS_KEY_PAIR+x} ] || [ ! -z ${AWS_KEY_PATH+x} ] ; then
      err "WARNING: AWS keys given but run-on option has value 'localhost'."
    fi
    if [ ! -z ${AWS_EC2_TYPE+x} ]; then
      err "WARNING: AWS instance type given but run-on option has value 'localhost'."
    fi
  fi

  if [ -z ${PG_VERSION+x} ]
  then
    err "WARNING: Postgres version not given. Will use version 10."
    PG_VERSION="10"
  fi

  if [ -z ${TMP_PATH+x} ]
  then
    TMP_PATH="/tmp"
    err "WARNING: Temp path not given. Will use $TMP_PATH"
  fi
  # create $TMP_PATH directory if not found, then create a subdirectory
  [ ! -d $TMP_PATH ] && mkdir $TMP_PATH
  TMP_PATH="$TMP_PATH/nancy_run_"$(date "+%Y%m%d_%H%M%S")
  [ ! -d $TMP_PATH ] && mkdir $TMP_PATH
  msg "Switched to a new sub-directory in the temp path: $TMP_PATH"

  workloads_count=0
  [ ! -z ${WORKLOAD_BASIS+x} ] && let workloads_count=$workloads_count+1
  [ ! -z ${WORKLOAD_REAL+x} ] && let workloads_count=$workloads_count+1
  [ ! -z ${WORKLOAD_CUSTOM_SQL+x} ] && let workloads_count=$workloads_count+1

  #--db-prepared-snapshot or --db-dump
  if ([ -z ${DB_PREPARED_SNAPSHOT+x} ]  &&  [ -z ${DB_DUMP_PATH+x} ]); then
    err "ERROR: The object (database) is not defined."
    exit 1;
  fi

  # --workload-real or --workload-basis-path or --workload-custom-sql
  if [ "$workloads_count" -eq "0" ]; then
    err "ERROR: The workload is not defined."
    exit 1;
  fi

  if  [ "$workloads_count" -gt "1" ]; then
    err "ERROR: 2 or more workload sources are given."
    exit 1
  fi

  if ([ ! -z ${DB_PREPARED_SNAPSHOT+x} ]  &&  [ ! -z ${DB_DUMP_PATH+x} ]); then
    err "ERROR: Both snapshot and dump sources are given."
    exit 1
  fi

  if [ ! -z ${DB_DUMP_PATH+x} ]; then
    checkPath DB_DUMP_PATH
    if [ "$?" -ne "0" ]; then
      echo "$DB_DUMP_PATH" > $TMP_PATH/db_dump_tmp.sql
      DB_DUMP_PATH="$TMP_PATH/db_dump_tmp.sql"
    else
      [ "$DEBUG" -eq "1" ] && msg "DEBUG: db-dump value will be considered as a file name."
    fi
    DB_DUMP_FILENAME=$(basename $DB_DUMP_PATH)
    DB_DUMP_EXT=${DB_DUMP_FILENAME##*.}
  else
    err "ERROR: file '$DB_DUMP_PATH' does not exist. "
    exit 1
  fi

  if [ -z ${PG_CONFIG+x} ]; then
    err "WARNING: No DB config provided. Will use the default one."
  else
    checkPath PG_CONFIG
    if [ "$?" -ne "0" ]; then
      #err "WARNING: Value given as pg_config: '$PG_CONFIG' not found as file will use as content"
      echo "$PG_CONFIG" > $TMP_PATH/pg_config_tmp.sql
      WORKLOAD_CUSTOM_SQL="$TMP_PATH/pg_config_tmp.sql"
    fi
  fi

  if ( \
    ([ -z ${TARGET_DDL_UNDO+x} ] && [ ! -z ${TARGET_DDL_DO+x} ]) \
    || ([ -z ${TARGET_DDL_DO+x} ] && [ ! -z ${TARGET_DDL_UNDO+x} ])
  ); then
    err "ERROR: both --target-ddl-do and --target-ddl-undo must be specified."
    exit 1;
  fi

  if [ -z ${ARTIFACTS_DESTINATION+x} ]; then
    err "WARNING: Artifacts destination not given. Will use ./"
    ARTIFACTS_DESTINATION="."
  fi

  if [ -z ${ARTIFACTS_FILENAME+x} ]
  then
    err "WARNING: Artifacts naming not set. Will use: $DOCKER_MACHINE"
    ARTIFACTS_FILENAME=$DOCKER_MACHINE
  fi

  [ ! -z ${WORKLOAD_REAL+x} ] && ! checkPath WORKLOAD_REAL \
    && err "ERROR: workload file $WORKLOAD_REAL not found" \
    && exit 1

  [ ! -z ${WORKLOAD_BASIS+x} ] && ! checkPath WORKLOAD_BASIS \
    && err "ERROR: workload file $WORKLOAD_BASIS not found" \
    && exit 1

  if [ ! -z ${WORKLOAD_CUSTOM_SQL+x} ]; then
    checkPath WORKLOAD_CUSTOM_SQL
    if [ "$?" -ne "0" ]; then
      #err "WARNING: Value given as workload-custom-sql: '$WORKLOAD_CUSTOM_SQL' not found as file will use as content"
      echo "$WORKLOAD_CUSTOM_SQL" > $TMP_PATH/workload_custom_sql_tmp.sql
      WORKLOAD_CUSTOM_SQL="$TMP_PATH/workload_custom_sql_tmp.sql"
    else
      [ "$DEBUG" -eq "1" ] && echo "DEBUG: Value given as workload-custom-sql will use as filename"
    fi
  fi

  if [ ! -z ${AFTER_DOCKER_INIT_CODE+x} ]; then
    checkPath AFTER_DOCKER_INIT_CODE
    if [ "$?" -ne "0" ]; then
      #err "WARNING: Value given as after_db_init_code: '$AFTER_DOCKER_INIT_CODE' not found as file will use as content"
      echo "$AFTER_DOCKER_INIT_CODE" > $TMP_PATH/after_docker_init_code_tmp.sh
      AFTER_DOCKER_INIT_CODE="$TMP_PATH/after_docker_init_code_tmp.sh"
    else
      [ "$DEBUG" -eq "1" ] && echo "DEBUG: Value given as commands-after-docker-init will use as filename"
    fi
  fi

  if [ ! -z ${AFTER_DB_INIT_CODE+x} ]; then
    checkPath AFTER_DB_INIT_CODE
    if [ "$?" -ne "0" ]; then
      #err "WARNING: Value given as after_db_init_code: '$AFTER_DB_INIT_CODE' not found as file will use as content"
      echo "$AFTER_DB_INIT_CODE" > $TMP_PATH/after_db_init_code_tmp.sql
      AFTER_DB_INIT_CODE="$TMP_PATH/after_db_init_code_tmp.sql"
    else
      [ "$DEBUG" -eq "1" ] && echo "DEBUG: Value given as sql-after-db-restore will use as filename"
    fi
  fi

  if [ ! -z ${BEFORE_DB_INIT_CODE+x} ]; then
    checkPath BEFORE_DB_INIT_CODE
    if [ "$?" -ne "0" ]; then
      #err "WARNING: Value given as before_db_init_code: '$BEFORE_DB_INIT_CODE' not found as file will use as content"
      echo "$BEFORE_DB_INIT_CODE" > $TMP_PATH/before_db_init_code_tmp.sql
      BEFORE_DB_INIT_CODE="$TMP_PATH/before_db_init_code_tmp.sql"
    else
      [ "$DEBUG" -eq "1" ] && echo "DEBUG: Value given as sql-before-db-restore will use as filename"
    fi
  fi

  if [ ! -z ${TARGET_DDL_DO+x} ]; then
    checkPath TARGET_DDL_DO
    if [ "$?" -ne "0" ]; then
      #err "WARNING: Value given as target_ddl_do: '$TARGET_DDL_DO' not found as file will use as content"
      echo "$TARGET_DDL_DO" > $TMP_PATH/target_ddl_do_tmp.sql
      TARGET_DDL_DO="$TMP_PATH/target_ddl_do_tmp.sql"
    else
      [ "$DEBUG" -eq "1" ] && echo "DEBUG: Value given as target_ddl_do will use as filename"
    fi
  fi

  if [ ! -z ${TARGET_DDL_UNDO+x} ]; then
    checkPath TARGET_DDL_UNDO
    if [ "$?" -ne "0" ]; then
      #err "WARNING: Value given as target_ddl_undo: '$TARGET_DDL_UNDO' not found as file will use as content"
      echo "$TARGET_DDL_UNDO" > $TMP_PATH/target_ddl_undo_tmp.sql
      TARGET_DDL_UNDO="$TMP_PATH/target_ddl_undo_tmp.sql"
    else
      [ "$DEBUG" -eq "1" ] && echo "DEBUG: Value given as target_ddl_undo will use as filename"
    fi
  fi

  if [ ! -z ${TARGET_CONFIG+x} ]; then
    checkPath TARGET_CONFIG
    if [ "$?" -ne "0" ]; then
      #err "WARNING: Value given as target_config: '$TARGET_CONFIG' not found as file will use as content"
      echo "$TARGET_CONFIG" > $TMP_PATH/target_config_tmp.conf
      TARGET_CONFIG="$TMP_PATH/target_config_tmp.conf"
    else
      [ "$DEBUG" -eq "1" ] && echo "DEBUG: Value given as target_config will use as filename"
    fi
  fi

  if [ ! -z ${EBS_VOLUME_SIZE+x} ]; then
    re='^[0-9]+$'
    if ! [[ $EBS_VOLUME_SIZE =~ $re ]] ; then
      err "ERROR: ebs-volume-size must be integer."
      exit 1
    fi
  else
    if [[ ! ${AWS_EC2_TYPE:0:2} == 'i3' ]]; then
      err "WARNING: ebs-volume-size is not given, will be calculated based on the dump size."
    fi
  fi
}

checkParams;

START_TIME=$(date +%s);

# Determine dump file size
if ([ "$RUN_ON" == "aws" ] && [ ! ${AWS_EC2_TYPE:0:2} == "i3" ] && \
   [ -z ${EBS_VOLUME_SIZE+x} ] && [ ! -z ${DB_DUMP_PATH+x} ]); then
    msg "Calculate EBS volume size."
    dumpFileSize=0
    if [[ $DB_DUMP_PATH =~ "s3://" ]]; then
      dumpFileSize=$(s3cmd info $DB_DUMP_PATH | grep "File size:" )
      dumpFileSize=${dumpFileSize/File size:/}
      dumpFileSize=${dumpFileSize/\t/}
      dumpFileSize=${dumpFileSize// /}
      [ $DEBUG -eq 1 ] && msg "S3 file size: $dumpFileSize"
    else
      dumpFileSize=$(wc -c "$DB_DUMP_PATH" | awk '{print $1}')
    fi
    let dumpFileSize=dumpFileSize*$EBS_SIZE_MULTIPLIER
    let minSize=300*$KB*$KB*$KB
    ebsSize=$minSize # 300 GB
    if [ "$dumpFileSize" -gt "$minSize" ]; then
        let ebsSize=$dumpFileSize
        ebsSize=$(numfmt --to-unit=G $ebsSize)
        EBS_VOLUME_SIZE=$ebsSize
        [ $DEBUG -eq 1 ] && msg "EBS volume size: $EBS_VOLUME_SIZE GB"
    else
      msg "EBS volume is not required."
    fi
fi

set -ueo pipefail
[ $DEBUG -eq 1 ] && set -uox pipefail # to debug
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
  if  [ "$DEBUG_TIMEOUT" -gt "0" ]; then
    msg "Debug timeout is $DEBUG_TIMEOUT seconds – started."
    msg "  To connect to the docker machine use:"
    msg "    docker \`docker-machine config $DOCKER_MACHINE\` exec -it pg_nancy_${CURRENT_TS} bash"
    sleep $DEBUG_TIMEOUT
  fi
  msg "Remove temp files..." # if exists
  docker $dockerConfig exec -i ${containerHash} bash -c "sudo rm -rf $MACHINE_HOME"
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
  if [ -z ${CONTAINER_ID+x} ]; then
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
    60 $AWS_KEY_PAIR $AWS_KEY_PATH $zone;
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
        60 $AWS_KEY_PAIR $AWS_KEY_PATH;
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
    if [ ! -z ${EBS_VOLUME_SIZE+x} ]; then
      msg "Create and attach a new EBS volume (size: $EBS_VOLUME_SIZE GB)"
      VOLUME_ID=$(aws ec2 create-volume --size $EBS_VOLUME_SIZE --region us-east-1 --availability-zone us-east-1a --volume-type gp2 | jq -r .VolumeId)
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
[ ! -z ${DB_DUMP_PATH+x} ] && copyFile $DB_DUMP_PATH
[ ! -z ${PG_CONFIG+x} ] && copyFile $PG_CONFIG
[ ! -z ${TARGET_CONFIG+x} ] && copyFile $TARGET_CONFIG
[ ! -z ${TARGET_DDL_DO+x} ] && copyFile $TARGET_DDL_DO
[ ! -z ${TARGET_DDL_UNDO+x} ] && copyFile $TARGET_DDL_UNDO
[ ! -z ${WORKLOAD_CUSTOM_SQL+x} ] && copyFile $WORKLOAD_CUSTOM_SQL
[ ! -z ${WORKLOAD_REAL+x} ] && copyFile $WORKLOAD_REAL

## Apply machine features
# Dump
sleep 2 # wait for postgres up&running
OP_START_TIME=$(date +%s);
if ([ ! -z ${AFTER_DOCKER_INIT_CODE+x} ] && [ "$AFTER_DOCKER_INIT_CODE" != "" ])
then
  msg "Apply code after docker init"
  AFTER_DOCKER_INIT_CODE_FILENAME=$(basename $AFTER_DOCKER_INIT_CODE)
  copyFile $AFTER_DOCKER_INIT_CODE
  # --set ON_ERROR_STOP=on
  docker_exec bash -c "chmod +x $MACHINE_HOME/$AFTER_DOCKER_INIT_CODE_FILENAME"
  docker_exec sh $MACHINE_HOME/$AFTER_DOCKER_INIT_CODE_FILENAME
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "After docker init code applied for $DURATION."
fi

OP_START_TIME=$(date +%s);
if ([ ! -z ${BEFORE_DB_INIT_CODE+x} ] && [ "$BEFORE_DB_INIT_CODE" != "" ]); then
  msg "Apply sql code before db init"
  BEFORE_DB_INIT_CODE_FILENAME=$(basename $BEFORE_DB_INIT_CODE)
  copyFile $BEFORE_DB_INIT_CODE
  # --set ON_ERROR_STOP=on
  docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres test -b -f $MACHINE_HOME/$BEFORE_DB_INIT_CODE_FILENAME $OUTPUT_REDIRECT"
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Before init SQL code applied for $DURATION."
fi
OP_START_TIME=$(date +%s);
msg "Restore database dump"
#CPU_CNT=$(cat /proc/cpuinfo | grep processor | wc -l)
CPU_CNT=$(docker_exec bash -c "cat /proc/cpuinfo | grep processor | wc -l") # for execute in docker
case "$DB_DUMP_EXT" in
  sql)
    docker_exec bash -c "cat $MACHINE_HOME/$DB_DUMP_FILENAME | psql --set ON_ERROR_STOP=on -U postgres test $OUTPUT_REDIRECT"
    ;;
  bz2)
    docker_exec bash -c "bzcat $MACHINE_HOME/$DB_DUMP_FILENAME | psql --set ON_ERROR_STOP=on -U postgres test $OUTPUT_REDIRECT"
    ;;
  gz)
    docker_exec bash -c "zcat $MACHINE_HOME/$DB_DUMP_FILENAME | psql --set ON_ERROR_STOP=on -U postgres test $OUTPUT_REDIRECT"
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
if ([ ! -z ${AFTER_DB_INIT_CODE+x} ] && [ "$AFTER_DB_INIT_CODE" != "" ]); then
  msg "Apply sql code after db init"
  AFTER_DB_INIT_CODE_FILENAME=$(basename $AFTER_DB_INIT_CODE)
  copyFile $AFTER_DB_INIT_CODE
  docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres test -b -f $MACHINE_HOME/$AFTER_DB_INIT_CODE_FILENAME $OUTPUT_REDIRECT"
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "After init SQL code applied for $DURATION."
fi
# Apply DDL code
OP_START_TIME=$(date +%s);
if ([ ! -z ${TARGET_DDL_DO+x} ] && [ "$TARGET_DDL_DO" != "" ]); then
  msg "Apply DDL SQL code"
  TARGET_DDL_DO_FILENAME=$(basename $TARGET_DDL_DO)
  docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres test -b -f $MACHINE_HOME/$TARGET_DDL_DO_FILENAME $OUTPUT_REDIRECT"
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Target DDL do code applied for $DURATION."
fi
# Apply initial postgres configuration
OP_START_TIME=$(date +%s);
if ([ ! -z ${PG_CONFIG+x} ] && [ "$PG_CONFIG" != "" ]); then
  msg "Apply initial postgres configuration"
  PG_CONFIG_FILENAME=$(basename $PG_CONFIG)
  docker_exec bash -c "cat $MACHINE_HOME/$PG_CONFIG_FILENAME >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
  if [ -z ${TARGET_CONFIG+x} ]
  then
    docker_exec bash -c "sudo /etc/init.d/postgresql restart"
  fi
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Initial configuration applied for $DURATION."
fi
# Apply postgres configuration
OP_START_TIME=$(date +%s);
if ([ ! -z ${TARGET_CONFIG+x} ] && [ "$TARGET_CONFIG" != "" ]); then
  msg "Apply postgres configuration"
  TARGET_CONFIG_FILENAME=$(basename $TARGET_CONFIG)
  docker_exec bash -c "cat $MACHINE_HOME/$TARGET_CONFIG_FILENAME >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
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
    docker_exec bash -c "psql -U postgres test -E -f $MACHINE_HOME/$WORKLOAD_CUSTOM_FILENAME $OUTPUT_REDIRECT"
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
if ([ ! -z ${TARGET_DDL_UNDO+x} ] && [ "$TARGET_DDL_UNDO" != "" ]); then
  msg "Apply DDL undo SQL code"
  TARGET_DDL_UNDO_FILENAME=$(basename $TARGET_DDL_UNDO)
  docker_exec bash -c "psql --set ON_ERROR_STOP=on -U postgres test -b -f $MACHINE_HOME/$TARGET_DDL_UNDO_FILENAME $OUTPUT_REDIRECT"
  END_TIME=$(date +%s);
  DURATION=$(echo $((END_TIME-OP_START_TIME)) | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}')
  msg "Target DDL undo code applied for $DURATION."
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
