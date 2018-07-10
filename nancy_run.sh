#!/bin/bash

DEBUG=0
CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
DOCKER_MACHINE="${DOCKER_MACHINE:-nancy-$CURRENT_TS}"
DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
DEBUG_TIMEOUT=0
EBS_SIZE_MULTIPLIER=15

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

    * 9.6 (default)

    * 10

    * 11devel (WIP)

  \033[1m--pg-config\033[22m (string)

  Specify PostgreSQL config to be used (may be partial).

  \033[1m--db-prepared-snapshot\033[22m (string)

  Reserved / Not yet implemented.

  \033[1m--db-dump-path\033[22m (string)

  Specify the path to database dump (created by pg_dump) to be used as an input.

  \033[1m--after-db-init-code\033[22m (string)

  Specify additional commands to be executed after database is initiated (dump
  loaded or snapshot attached).

  \033[1m--workload-full-path\033[22m (string)

  Path to 'real' workload prepared by using 'nancy prepare-workload'.

  \033[1m--workload-basis-path\033[22m (string)

  Reserved / Not yet implemented.

  \033[1m--workload-custom-sql\033[22m (string)

  Specify custom SQL queries to be used as an input.

  \033[1m--workload-replay-speed\033[22m (string)

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
    -d | --debug ) DEBUG=1; shift ;;
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
    --db-dump-path )
        DB_DUMP_PATH="$2"; shift 2 ;;
    --after-db-init-code )
        #s3 url|filename|content
        AFTER_DB_INIT_CODE="$2"; shift 2 ;;
    --workload-full-path )
        #s3 url
        WORKLOAD_FULL_PATH="$2"; shift 2 ;;
    --workload-basis-path )
        #Still unsuported
        WORKLOAD_BASIS_PATH="$2"; shift 2 ;;
    --workload-custom-sql )
        #s3 url|filename|content
        WORKLOAD_CUSTOM_SQL="$2"; shift 2 ;;
    --workload-replay-speed )
        WORKLOAD_REPLAY_SPEED="$2"; shift 2 ;;
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
    -- ) shift; break ;;
    * ) break ;;
  esac
done

RUN_ON=${RUN_ON:-localhost}

if [ $DEBUG -eq 1 ]
then
    echo "debug: ${DEBUG}"
    echo "run_on: ${RUN_ON}"
    echo "container_id: ${CONTAINER_ID}"
    echo "aws_ec2_type: ${AWS_EC2_TYPE}"
    echo "aws-key-pair: $AWS_KEY_PAIR"
    echo "aws-key-path: $AWS_KEY_PATH"
    echo "pg_version: ${PG_VERSION}"
    echo "pg_config: ${PG_CONFIG}"
    echo "db_prepared_snapshot: ${DB_PREPARED_SNAPSHOT}"
    echo "db_dump_path: $DB_DUMP_PATH"
    echo "workload_full_path: $WORKLOAD_FULL_PATH"
    echo "workload_basis_path: $WORKLOAD_BASIS_PATH"
    echo "workload_custom_sql: $WORKLOAD_CUSTOM_SQL"
    echo "workload_replay_speed: $WORKLOAD_REPLAY_SPEED"
    echo "target_ddl_do: $TARGET_DDL_DO"
    echo "target_ddl_undo: $TARGET_DDL_UNDO"
    echo "target_config: $TARGET_CONFIG"
    echo "artifacts_destination: $ARTIFACTS_DESTINATION"
    echo "s3-cfg-path: $S3_CFG_PATH"
    echo "tmp-path: $TMP_PATH"
    echo "after-db-init-code: $AFTER_DB_INIT_CODE"
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
    echo "CHECK $path"
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
  if [ "$RUN_ON" != "aws" ] && [ "$RUN_ON" != "localhost" ]; then
    >&2 echo "ERROR: incorrect value for option --run-on"
    exit 1
  fi
  if [ "$RUN_ON" = "aws" ]; then
    if [ ! -z ${CONTAINER_ID+x} ]
    then
      >&2 echo "ERROR: Container ID may be specified only for local runs."
      exit 1
    fi
    if [ -z ${AWS_KEY_PAIR+x} ] || [ -z ${AWS_KEY_PATH+x} ]
    then
      >&2 echo "ERROR: AWS keys not given."
      exit 1
    else
      checkPath AWS_KEY_PATH
    fi

    if [ -z ${AWS_EC2_TYPE+x} ]
    then
      >&2 echo "ERROR: AWS EC2 Instance type not given."
      exit 1
    fi
  fi

  if [ -z ${PG_VERSION+x} ]
  then
    >&2 echo "WARNING: Postgres version not given. Will use 9.6."
    PG_VERSION="9.6"
  fi

  if [ -z ${TMP_PATH+x} ]
  then
    TMP_PATH="/var/tmp/nancy_run"
    >&2 echo "WARNING: Temp path not given. Will use $TMP_PATH"
  fi
  #make tmp path if not found
  [ ! -d $TMP_PATH ] && mkdir $TMP_PATH

  workloads_count=0
  [ ! -z ${WORKLOAD_BASIS_PATH+x} ] && let workloads_count=$workloads_count+1
  [ ! -z ${WORKLOAD_FULL_PATH+x} ] && let workloads_count=$workloads_count+1
  [ ! -z ${WORKLOAD_CUSTOM_SQL+x} ] && let workloads_count=$workloads_count+1

  # --workload-full-path or --workload-basis-path or --workload-custom-sql
  if [ "$workloads_count" -eq "0" ]
  then
    >&2 echo "ERROR: Workload not given."
    exit 1;
  fi

  if  [ "$workloads_count" -gt "1" ]
  then
    >&2 echo "ERROR: 2 or more workload sources are given."
    exit 1
  fi

  #--db-prepared-snapshot or --db-dump-path
  if ([ -z ${DB_PREPARED_SNAPSHOT+x} ]  &&  [ -z ${DB_DUMP_PATH+x} ]); then
    >&2 echo "ERROR: Snapshot or dump not given."
    exit 1;
  fi

  if ([ ! -z ${DB_PREPARED_SNAPSHOT+x} ]  &&  [ ! -z ${DB_DUMP_PATH+x} ])
  then
    >&2 echo "ERROR: Both snapshot and dump sources are given."
    exit 1
  fi

  [ ! -z ${DB_DUMP_PATH+x} ] && ! checkPath DB_DUMP_PATH \
    && >&2 echo "ERROR: file $DB_DUMP_PATH given by db_dump_path not found" \
    && exit 1

  if [ -z ${PG_CONFIG+x} ]; then
    >&2 echo "WARNING: No DB config provided. Using default one."
  else
    checkPath PG_CONFIG
    if [ "$?" -ne "0" ]; then
      #>&2 echo "WARNING: Value given as pg_config: '$PG_CONFIG' not found as file will use as content"
      echo "$PG_CONFIG" > $TMP_PATH/pg_config_tmp.sql
      WORKLOAD_CUSTOM_SQL="$TMP_PATH/pg_config_tmp.sql"
    fi
  fi

  if ( \
    ([ -z ${TARGET_DDL_UNDO+x} ] && [ ! -z ${TARGET_DDL_DO+x} ]) \
    || ([ -z ${TARGET_DDL_DO+x} ] && [ ! -z ${TARGET_DDL_UNDO+x} ])
  ); then
    >&2 echo "ERROR: DDL code must have do and undo part."
    exit 1;
  fi

  if [ -z ${ARTIFACTS_DESTINATION+x} ]; then
    >&2 echo "WARNING: Artifacts destination not given. Will use ./"
    ARTIFACTS_DESTINATION="."
  fi

  if [ -z ${ARTIFACTS_FILENAME+x} ]
  then
    >&2 echo "WARNING: Artifacts naming not set. Will use: $DOCKER_MACHINE"
    ARTIFACTS_FILENAME=$DOCKER_MACHINE
  fi

  [ ! -z ${WORKLOAD_FULL_PATH+x} ] && ! checkPath WORKLOAD_FULL_PATH \
    && >&2 echo "ERROR: workload file $WORKLOAD_FULL_PATH not found" \
    && exit 1

  [ ! -z ${WORKLOAD_BASIS_PATH+x} ] && ! checkPath WORKLOAD_BASIS_PATH \
    && >&2 echo "ERROR: workload file $WORKLOAD_BASIS_PATH not found" \
    && exit 1

  if [ ! -z ${WORKLOAD_CUSTOM_SQL+x} ]; then
    checkPath WORKLOAD_CUSTOM_SQL
    if [ "$?" -ne "0" ]; then
      #>&2 echo "WARNING: Value given as workload-custom-sql: '$WORKLOAD_CUSTOM_SQL' not found as file will use as content"
      echo "$WORKLOAD_CUSTOM_SQL" > $TMP_PATH/workload_custom_sql_tmp.sql
      WORKLOAD_CUSTOM_SQL="$TMP_PATH/workload_custom_sql_tmp.sql"
    else
      [ "$DEBUG" -eq "1" ] && echo "DEBUG: Value given as workload-custom-sql will use as filename"
    fi
  fi

  if [ ! -z ${AFTER_DB_INIT_CODE+x} ]; then
    checkPath AFTER_DB_INIT_CODE
    if [ "$?" -ne "0" ]; then
      #>&2 echo "WARNING: Value given as after_db_init_code: '$AFTER_DB_INIT_CODE' not found as file will use as content"
      echo "$AFTER_DB_INIT_CODE" > $TMP_PATH/after_db_init_code_tmp.sql
      AFTER_DB_INIT_CODE="$TMP_PATH/after_db_init_code_tmp.sql"
    else
      [ "$DEBUG" -eq "1" ] && echo "DEBUG: Value given as after_db_init_code will use as filename"
    fi
  fi

  if [ ! -z ${TARGET_DDL_DO+x} ]; then
    checkPath TARGET_DDL_DO
    if [ "$?" -ne "0" ]; then
      #>&2 echo "WARNING: Value given as target_ddl_do: '$TARGET_DDL_DO' not found as file will use as content"
      echo "$TARGET_DDL_DO" > $TMP_PATH/target_ddl_do_tmp.sql
      TARGET_DDL_DO="$TMP_PATH/target_ddl_do_tmp.sql"
    else
      [ "$DEBUG" -eq "1" ] && echo "DEBUG: Value given as target_ddl_do will use as filename"
    fi
  fi

  if [ ! -z ${TARGET_DDL_UNDO+x} ]; then
    checkPath TARGET_DDL_UNDO
    if [ "$?" -ne "0" ]; then
      #>&2 echo "WARNING: Value given as target_ddl_undo: '$TARGET_DDL_UNDO' not found as file will use as content"
      echo "$TARGET_DDL_UNDO" > $TMP_PATH/target_ddl_undo_tmp.sql
      TARGET_DDL_UNDO="$TMP_PATH/target_ddl_undo_tmp.sql"
    else
      [ "$DEBUG" -eq "1" ] && echo "DEBUG: Value given as target_ddl_undo will use as filename"
    fi
  fi

  if [ ! -z ${TARGET_CONFIG+x} ]; then
    checkPath TARGET_CONFIG
    if [ "$?" -ne "0" ]; then
      #>&2 echo "WARNING: Value given as target_config: '$TARGET_CONFIG' not found as file will use as content"
      echo "$TARGET_CONFIG" > $TMP_PATH/target_config_tmp.conf
      TARGET_CONFIG="$TMP_PATH/target_config_tmp.conf"
    else
      [ "$DEBUG" -eq "1" ] && echo "DEBUG: Value given as target_config will use as filename"
    fi
  fi
}

checkParams;

# Determine dump file size
if [ ! -z ${DB_DUMP_PATH+x} ]; then
    dumpFileSize=0
    if [[ $DB_DUMP_PATH =~ "s3://" ]]; then
      dumpFileSize=$(s3cmd info $DB_DUMP_PATH | grep "File size:" )
      dumpFileSize=${dumpFileSize/File size:/}
      dumpFileSize=${dumpFileSize/\t/}
      dumpFileSize=${dumpFileSize// /}
      #echo "S3 FILESIZE: $dumpFileSize"
    else
      dumpFileSize=$(stat -c%s "$DB_DUMP_PATH")
    fi
    [ $DEBUG -eq 1 ] && echo "Dump filesize: $dumpFileSize bytes"
    KB=1024
    let minSize=300*$KB*$KB*$KB
    ebsSize=$minSize # 300 GB
    if [ "$dumpFileSize" -gt "$minSize" ]; then
        let ebsSize=$dumpFileSize
        let ebsSize=$ebsSize*$EBS_SIZE_MULTIPLIER
        ebsSize=$(numfmt --to-unit=G $ebsSize)
        EBS_SIZE=$ebsSize
        [ $DEBUG -eq 1 ] && echo "EBS Size: $EBS_SIZE Gb"
    fi
fi

set -ueo pipefail
[ $DEBUG -eq 1 ] && set -ueox pipefail # to debug
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
    if [ $checkPrice -eq 1 ]
    then
      status=$( \
        aws ec2 describe-spot-instance-requests \
        --filters="Name=launch.instance-type,Values=$AWS_EC2_TYPE" \
        | jq  '.SpotInstanceRequests | sort_by(.CreateTime) | .[] | .Status.Code' \
        | tail -n 1
      )
      if [ "$status" == "\"price-too-low\"" ]
      then
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
  echo "Attempt to create a docker machine..."
  docker-machine create --driver=amazonec2 \
    --amazonec2-request-spot-instance \
    --amazonec2-keypair-name="$5" \
    --amazonec2-ssh-keypath="$6" \
    --amazonec2-block-duration-minutes=$4 \
    --amazonec2-instance-type=$2 \
    --amazonec2-spot-price=$3 \
    $1 2> >(grep -v "failed waiting for successful resource state" >&2) &
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
  echo "Termination requested for machine '$1', current status: $cmdout"
}

function cleanupAndExit {
  echo "Remove temp files..." # if exists
  rm -f "$TMP_PATH/after_db_init_code_tmp.sql"
  rm -f "$TMP_PATH/workload_custom_sql_tmp.sql"
  rm -f "$TMP_PATH/target_ddl_do_tmp.sql"
  rm -f "$TMP_PATH/target_ddl_undo_tmp.sql"
  rm -f "$TMP_PATH/target_config_tmp.conf"
  rm -f "$TMP_PATH/pg_config_tmp.conf"
  if [ "$RUN_ON" = "localhost" ]; then
    rm -rf "$TMP_PATH/nancy_${containerHash}"
    echo "Remove docker container"
    docker container rm -f $containerHash
  elif [ "$RUN_ON" = "aws" ]; then
    destroyDockerMachine $DOCKER_MACHINE
    if [ ! -z ${VOLUME_ID+x} ]; then
        echo "Wait and delete volume $VOLUME_ID"
        sleep 60 # wait to machine removed
        delvolout=$(aws ec2 delete-volume --volume-id $VOLUME_ID)
        echo "Volume $VOLUME_ID deleted"
    fi    
  else
    >&2 echo "ASSERT: must not reach this point"
    exit 1
  fi
}
trap cleanupAndExit EXIT

if [[ "$RUN_ON" = "localhost" ]]; then
  if [ -z ${CONTAINER_ID+x} ]; then
    containerHash=$(docker run --name="pg_nancy_${CURRENT_TS}" \
      -v $TMP_PATH:/machine_home \
      -dit "postgresmen/postgres-with-stuff:pg${PG_VERSION}" \
    )
  else
    containerHash="$CONTAINER_ID"
  fi
  dockerConfig=""
elif [[ "$RUN_ON" = "aws" ]]; then
  ## Get max price from history and apply multiplier
  # TODO detect region and/or allow to choose via options
  prices=$(
    aws --region=us-east-1 ec2 \
    describe-spot-price-history --instance-types $AWS_EC2_TYPE --no-paginate \
    --start-time=$(date +%s) --product-descriptions="Linux/UNIX (Amazon VPC)" \
    --query 'SpotPriceHistory[*].{az:AvailabilityZone, price:SpotPrice}'
  )
  maxprice=$(echo $prices | jq 'max_by(.price) | .price')
  maxprice="${maxprice/\"/}"
  maxprice="${maxprice/\"/}"
  echo "Max price from history: $maxprice"
  multiplier="1.1"
  price=$(echo "$maxprice * $multiplier" | bc -l)
  echo "Increased price: $price"
  EC2_PRICE=$price

  createDockerMachine $DOCKER_MACHINE $AWS_EC2_TYPE $EC2_PRICE \
    60 $AWS_KEY_PAIR $AWS_KEY_PATH;
  status=$(waitEC2Ready "docker-machine create" "$DOCKER_MACHINE" 1)
  if [ "$status" == "price-too-low" ]
  then
    echo "Price $price is too low for $AWS_EC2_TYPE instance. Getting the up-to-date value from the error message..."

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
    if [ "$corrrectPriceForLastFailedRequest" != "" ]  &&  [ "$corrrectPriceForLastFailedRequest" != "null" ]; then
      EC2_PRICE=$corrrectPriceForLastFailedRequest
      #update docker machine name
      CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
      DOCKER_MACHINE="nancy-$CURRENT_TS"
      DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
      #try start docker machine name with new price
      echo "Attempt to create a new docker machine: $DOCKER_MACHINE with price: $EC2_PRICE."
      createDockerMachine $DOCKER_MACHINE $AWS_EC2_TYPE $EC2_PRICE \
        60 $AWS_KEY_PAIR $AWS_KEY_PATH;
      waitEC2Ready "docker-machine create" "$DOCKER_MACHINE" 0;
    else
      >&2 echo "ERROR: Cannot determine actual price for the instance $AWS_EC2_TYPE."
      exit 1;
    fi
  fi

  echo "Check a docker machine status."
  res=$(docker-machine status $DOCKER_MACHINE 2>&1 &)
  if [ "$res" != "Running" ]
  then
    >&2 echo "Failed: Docker $DOCKER_MACHINE is NOT running."
    exit 1;
  fi

  echo "Docker $DOCKER_MACHINE is running."

  if [ ${AWS_EC2_TYPE:0:2} == 'i3' ]
  then
    # Init i3 storage, just mount existing volume
    echo "Attach i3 nvme volume"
    docker-machine ssh $DOCKER_MACHINE df -h
    docker-machine ssh $DOCKER_MACHINE sudo add-apt-repository -y ppa:sbates
    docker-machine ssh $DOCKER_MACHINE sudo apt-get update || :
    docker-machine ssh $DOCKER_MACHINE sudo apt-get install -y nvme-cli

    docker-machine ssh $DOCKER_MACHINE echo "# partition table of /dev/nvme0n1" > /tmp/nvme.part
    docker-machine ssh $DOCKER_MACHINE echo "unit: sectors " >> /tmp/nvme.part
    docker-machine ssh $DOCKER_MACHINE echo "/dev/nvme0n1p1 : start=     2048, size=1855466702, Id=83 " >> /tmp/nvme.part
    docker-machine ssh $DOCKER_MACHINE echo "/dev/nvme0n1p2 : start=        0, size=        0, Id= 0 " >> /tmp/nvme.part
    docker-machine ssh $DOCKER_MACHINE echo "/dev/nvme0n1p3 : start=        0, size=        0, Id= 0 " >> /tmp/nvme.part
    docker-machine ssh $DOCKER_MACHINE echo "/dev/nvme0n1p4 : start=        0, size=        0, Id= 0 " >> /tmp/nvme.part

    docker-machine ssh $DOCKER_MACHINE sudo sfdisk /dev/nvme0n1 < /tmp/nvme.part
    docker-machine ssh $DOCKER_MACHINE sudo mkfs -t ext4 /dev/nvme0n1p1
    docker-machine ssh $DOCKER_MACHINE "sudo sh -c \"mkdir /home/storage\""
    docker-machine ssh $DOCKER_MACHINE sudo mount /dev/nvme0n1p1 /home/storage
#    docker-machine ssh $DOCKER_MACHINE "sudo sh -c \"echo 'Check mount storage TEST' > /home/storage/nvme0n1p1-test.txt\""
    docker-machine ssh $DOCKER_MACHINE df -h
  else
    # Create new volume and attach them for non i3 instances if need
    if [ ! -z ${EBS_SIZE+x} ]; then
      echo "Create and attach EBS volume"
      [ $DEBUG -eq 1 ] && echo "Create volume with size: $EBS_SIZE Gb"
      VOLUME_ID=$(aws ec2 create-volume --size 10 --region us-east-1 --availability-zone us-east-1a --volume-type gp2 | jq -r .VolumeId)
      INSTANCE_ID=$(docker-machine ssh $DOCKER_MACHINE curl -s http://169.254.169.254/latest/meta-data/instance-id)
      sleep 10 # wait to volume will ready
      attachResult=$(aws ec2 attach-volume --device /dev/xvdf --volume-id $VOLUME_ID --instance-id $INSTANCE_ID --region us-east-1)
      docker-machine ssh $DOCKER_MACHINE sudo mkfs.ext4 /dev/xvdf
      docker-machine ssh $DOCKER_MACHINE "sudo sh -c \"mkdir /home/storage\""
      docker-machine ssh $DOCKER_MACHINE sudo mount /dev/xvdf /home/storage
      #    docker-machine ssh $DOCKER_MACHINE "sudo sh -c \"echo 'Check mount storage TEST' > /home/storage/xvdf-test.txt\""
    fi
  fi

  containerHash=$( \
    docker `docker-machine config $DOCKER_MACHINE` run \
      --name="pg_nancy_${CURRENT_TS}" \
      -v /home/ubuntu:/machine_home \
      -v /home/storage:/storage \
      -dit "postgresmen/postgres-with-stuff:pg${PG_VERSION}"
  )
  dockerConfig=$(docker-machine config $DOCKER_MACHINE)
else
  >&2 echo "ASSERT: must not reach this point"
  exit 1
fi

alias docker_exec='docker $dockerConfig exec -i ${containerHash} '

MACHINE_HOME="/machine_home/nancy_${containerHash}"
docker_exec sh -c "mkdir $MACHINE_HOME && chmod a+w $MACHINE_HOME"

#docker_exec bash -c "ls -al /storage/"

function copyFile() {
  if [ "$1" != '' ]; then
    if [[ "$1" =~ "s3://" ]]; then # won't work for .s3cfg!
      docker_exec s3cmd sync $1 $MACHINE_HOME/
    else
      if [ "$RUN_ON" = "localhost" ]; then
        #ln ${1/file:\/\//} "$TMP_PATH/nancy_$containerHash/"
        # TODO: option – hard links OR regular `cp`
        docker cp ${1/file:\/\//} $containerHash:$MACHINE_HOME/
      elif [ "$RUN_ON" = "aws" ]; then
        docker-machine scp $1 $DOCKER_MACHINE:/home/ubuntu/nancy_${containerHash}
      else
        >&2 echo "ASSERT: must not reach this point"
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
[ ! -z ${WORKLOAD_FULL_PATH+x} ] && copyFile $WORKLOAD_FULL_PATH

## Apply machine features
# Dump
sleep 2 # wait for postgres up&running
DB_DUMP_FILENAME=$(basename $DB_DUMP_PATH)
docker_exec bash -c "bzcat $MACHINE_HOME/$DB_DUMP_FILENAME | psql --set ON_ERROR_STOP=on -U postgres test"
# After init database sql code apply
echo "Apply sql code after db init"
if ([ ! -z ${AFTER_DB_INIT_CODE+x} ] && [ "$AFTER_DB_INIT_CODE" != "" ])
then
  AFTER_DB_INIT_CODE_FILENAME=$(basename $AFTER_DB_INIT_CODE)
  if [[ $AFTER_DB_INIT_CODE =~ "s3://" ]]; then
    docker_exec s3cmd sync $AFTER_DB_INIT_CODE $MACHINE_HOME/
  else
    docker-machine scp $AFTER_DB_INIT_CODE $DOCKER_MACHINE:/home/ubuntu/nancy_$containerHash
  fi
  docker_exec bash -c "psql -U postgres test -E -f $MACHINE_HOME/$AFTER_DB_INIT_CODE_FILENAME"
fi
# Apply DDL code
echo "Apply DDL SQL code"
if ([ ! -z ${TARGET_DDL_DO+x} ] && [ "$TARGET_DDL_DO" != "" ]); then
  TARGET_DDL_DO_FILENAME=$(basename $TARGET_DDL_DO)
  docker_exec bash -c "psql -U postgres test -E -f $MACHINE_HOME/$TARGET_DDL_DO_FILENAME"
fi
# Apply initial postgres configuration
echo "Apply initial postgres configuration"
if ([ ! -z ${PG_CONFIG+x} ] && [ "$PG_CONFIG" != "" ]); then
  PG_CONFIG_FILENAME=$(basename $PG_CONFIG)
  docker_exec bash -c "cat $MACHINE_HOME/$PG_CONFIG_FILENAME >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
  if [ -z ${TARGET_CONFIG+x} ]
  then
    docker_exec bash -c "sudo /etc/init.d/postgresql restart"
  fi
fi
# Apply postgres configuration
echo "Apply postgres configuration"
if ([ ! -z ${TARGET_CONFIG+x} ] && [ "$TARGET_CONFIG" != "" ]); then
  TARGET_CONFIG_FILENAME=$(basename $TARGET_CONFIG)
  docker_exec bash -c "cat $MACHINE_HOME/$TARGET_CONFIG_FILENAME >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
  docker_exec bash -c "sudo /etc/init.d/postgresql restart"
fi
# Clear statistics and log
echo "Execute vacuumdb..."
docker_exec vacuumdb -U postgres test -j $(cat /proc/cpuinfo | grep processor | wc -l) --analyze
docker_exec bash -c "echo '' > /var/log/postgresql/postgresql-$PG_VERSION-main.log"
# Execute workload
echo "Execute workload..."
if [ ! -z ${WORKLOAD_FULL_PATH+x} ] && [ "$WORKLOAD_FULL_PATH" != '' ];then
  echo "Execute pgreplay queries..."
  docker_exec psql -U postgres test -c 'create role testuser superuser login;'
  WORKLOAD_FILE_NAME=$(basename $WORKLOAD_FULL_PATH)
  docker_exec bash -c "pgreplay -r -j $MACHINE_HOME/$WORKLOAD_FILE_NAME"
else
  if ([ ! -z ${WORKLOAD_CUSTOM_SQL+x} ] && [ "$WORKLOAD_CUSTOM_SQL" != "" ]); then
    WORKLOAD_CUSTOM_FILENAME=$(basename $WORKLOAD_CUSTOM_SQL)
    echo "Execute custom sql queries..."
    docker_exec bash -c "psql -U postgres test -E -f $MACHINE_HOME/$WORKLOAD_CUSTOM_FILENAME"
  fi
fi

## Get statistics
echo "Prepare JSON log..."
docker_exec bash -c "/root/pgbadger/pgbadger \
  -j $(cat /proc/cpuinfo | grep processor | wc -l) \
  --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' /var/log/postgresql/* -f stderr \
  -o $MACHINE_HOME/$ARTIFACTS_FILENAME.json"

echo "Save JSON log..."
if [[ $ARTIFACTS_DESTINATION =~ "s3://" ]]; then
    docker_exec s3cmd put /$MACHINE_HOME/$ARTIFACTS_FILENAME.json \
      $ARTIFACTS_DESTINATION/
else
    logpath=$( \
      docker_exec bash -c "psql -XtU postgres \
        -c \"select string_agg(setting, '/' order by name) from pg_settings where name in ('log_directory', 'log_filename');\" \
        | grep / | sed -e 's/^[ \t]*//'"
    )
    docker_exec bash -c "gzip -c $logpath > $MACHINE_HOME/$ARTIFACTS_FILENAME.log.gz"
    if [ "$RUN_ON" = "localhost" ]; then
      docker cp $containerHash:$MACHINE_HOME/$ARTIFACTS_FILENAME.json $ARTIFACTS_DESTINATION/
      docker cp $containerHash:$MACHINE_HOME/$ARTIFACTS_FILENAME.log.gz $ARTIFACTS_DESTINATION/
      # TODO option: ln / cp
      #cp "$TMP_PATH/nancy_$containerHash/"$ARTIFACTS_FILENAME.json $ARTIFACTS_DESTINATION/
      #cp "$TMP_PATH/nancy_$containerHash/"$ARTIFACTS_FILENAME.log.gz $ARTIFACTS_DESTINATION/
    elif [ "$RUN_ON" = "aws" ]; then
      docker-machine scp $DOCKER_MACHINE:/home/ubuntu/nancy_$containerHash/$ARTIFACTS_FILENAME.json $ARTIFACTS_DESTINATION/
      docker-machine scp $DOCKER_MACHINE:/home/ubuntu/nancy_$containerHash/$ARTIFACTS_FILENAME.log.gz $ARTIFACTS_DESTINATION/
    else
      >&2 echo "ASSERT: must not reach this point"
      exit 1
    fi
fi

echo "Apply DDL undo SQL code"
if ([ ! -z ${TARGET_DDL_UNDO+x} ] && [ "$TARGET_DDL_UNDO" != "" ]); then
    TARGET_DDL_UNDO_FILENAME=$(basename $TARGET_DDL_UNDO)
    docker_exec bash -c "psql -U postgres test -E -f $MACHINE_HOME/$TARGET_DDL_UNDO_FILENAME"
fi

echo -e "Run done!"
echo -e "Report: $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME.json"
echo -e "Query log: $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME.log.gz"
echo -e "-------------------------------------------"
echo -e "Summary:"
echo -e "  Queries duration:\t\t" $(cat $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME.json | jq '.overall_stat.queries_duration') " ms"
echo -e "  Queries count:\t\t" $(cat $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME.json | jq '.overall_stat.queries_number')
echo -e "  Normalized queries count:\t" $(cat $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME.json | jq '.normalyzed_info| length')
echo -e "  Errors count:\t\t\t" $(cat $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME.json | jq '.overall_stat.errors_number')
echo -e "-------------------------------------------"

sleep $DEBUG_TIMEOUT

echo Bye!
