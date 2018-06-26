#!/bin/bash

DEBUG=0
CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
DOCKER_MACHINE="${DOCKER_MACHINE:-nancy-$CURRENT_TS}"
DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
DEBUG_TIMEOUT=0

## Get command line params
while true; do
  case "$1" in
    -d | --debug ) DEBUG=1; shift ;;
    --run-on )
        RUN_ON="$2"; shift 2 ;;
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
        #s3 url|filename +
        AFTER_DB_INIT_CODE="$2"; shift 2 ;;
    --workload-full-path )
        #s3 url
        WORKLOAD_FULL_PATH="$2"; shift 2 ;;
    --workload-basis-path )
        #Still unsuported
        WORKLOAD_BASIS_PATH="$2"; shift 2 ;;
    --workload-custom-sql )
        #s3 url|filename +
        WORKLOAD_CUSTOM_SQL="$2"; shift 2 ;;
    --workload-replay-speed )
        WORKLOAD_REPLAY_SPEED="$2"; shift 2 ;;
    --target-ddl-do )
        #s3 url|filename +
        TARGET_DDL_DO="$2"; shift 2 ;;
    --target-ddl-undo )
        #s3 url|filename +
        TARGET_DDL_UNDO="$2"; shift 2 ;;
    --target-config )
        #s3 url|filename +
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

    --s3-cfg-path )
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
    if [ ! -v $1 ]
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
            return 3 # file not found
        fi
    fi
    if [ -f $path ]
    then
        return 0;
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
      if [ ! -v AWS_KEY_PAIR ] || [ ! -v AWS_KEY_PATH ]
      then
          >&2 echo "ERROR: AWS keys not given."
          exit 1
      fi

      if [ ! -v AWS_EC2_TYPE ]
      then
          >&2 echo "ERROR: AWS EC2 Instance type not given."
          exit 1
      fi
    fi

    if [ ! -v PG_VERSION ]
    then
        >&2 echo "WARNING: Postgres version not given. Will use 9.6."
        PG_VERSION="9.6"
    fi

    if [ ! -v TMP_PATH ]
    then
        TMP_PATH="/var/tmp/nancy_run"
        >&2 echo "WARNING: Temp path not given. Will use $TMP_PATH"
    fi
    #make tmp path if not found
    [ ! -d $TMP_PATH ] && mkdir $TMP_PATH

    if [ ! -v S3_CFG_PATH ]
    then
        >&2 echo "WARNING: S3 config file path not given. Will use ~/.s3cfg"
        S3_CFG_PATH=$(echo ~)"/.s3cfg"
    fi

    workloads_count=0
    [ -v WORKLOAD_BASIS_PATH ] && let workloads_count=$workloads_count+1
    [ -v WORKLOAD_FULL_PATH ] && let workloads_count=$workloads_count+1
    [ -v WORKLOAD_CUSTOM_SQL ] && let workloads_count=$workloads_count+1

    # --workload-full-path or --workload-basis-path or --workload-custom-sql
    if [ "$workloads_count" -eq "0" ]
    then
        >&2 echo "ERROR: Workload not given."
        exit 1;
    fi

    if  [ "$workloads_count" -gt "1" ]
    then
        >&2 echo "ERROR: 2 or more workload source given."
        exit 1
    fi

    #--db-prepared-snapshot or --db-dump-path
    if ([ ! -v DB_PREPARED_SNAPSHOT ]  &&  [ ! -v DB_DUMP_PATH ])
    then
        >&2 echo "ERROR: Snapshot or dump not given."
        exit 1;
    fi

    if ([ -v DB_PREPARED_SNAPSHOT ]  &&  [ -v DB_DUMP_PATH ])
    then
        >&2 echo "ERROR: Both snapshot and dump sources given."
        exit 1
    fi

    if (([ ! -v TARGET_DDL_UNDO ] && [ -v TARGET_DDL_DO ]) || ([ ! -v TARGET_DDL_DO ] && [ -v TARGET_DDL_UNDO ]))
    then
        >&2 echo "ERROR: DDL code must have do and undo part."
        exit 1;
    fi

    if [ ! -v ARTIFACTS_DESTINATION ]
    then
        >&2 echo "WARNING: Artifacts destination not given. Will use ./"
        ARTIFACTS_DESTINATION="."
    fi

    if [ ! -v ARTIFACTS_FILENAME ]
    then
        >&2 echo "WARNING: Artifacts destination not given. Will use $DOCKER_MACHINE"
        ARTIFACTS_FILENAME=$DOCKER_MACHINE
    fi

    [ -v WORKLOAD_FULL_PATH ] && ! checkPath WORKLOAD_FULL_PATH && >&2 echo "WARNING: file $AFTER_DB_INIT_CODE not found"

    [ -v WORKLOAD_BASIS_PATH ] && ! checkPath WORKLOAD_BASIS_PATH && >&2 echo "WARNING: file $WORKLOAD_BASIS_PATH not found"

    [ -v WORKLOAD_CUSTOM_SQL ] && ! checkPath WORKLOAD_CUSTOM_SQL && >&2 echo "WARNING: file $WORKLOAD_CUSTOM_SQL not found"

    [ -v DB_DUMP_PATH ] && ! checkPath DB_DUMP_PATH && >&2 echo "WARNING: file $DB_DUMP_PATH not found"

    [ -v AFTER_DB_INIT_CODE ] && ! checkPath AFTER_DB_INIT_CODE && >&2 echo "WARNING: file $AFTER_DB_INIT_CODE not found"

    [ -v TARGET_DDL_DO ] && ! checkPath TARGET_DDL_DO && >&2 echo "WARNING: file $TARGET_DDL_DO not found"

    [ -v TARGET_DDL_UNDO ] && ! checkPath TARGET_DDL_UNDO && >&2 echo "WARNING: file $TARGET_DDL_UNDO not found"

    [ -v TARGET_CONFIG ] && ! checkPath TARGET_CONFIG && >&2 echo "WARNING: file $TARGET_CONFIG not found"
}

checkParams;

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
            #status=$(aws ec2 describe-spot-instance-requests --filters="Name=launch.instance-type,Values=$AWS_EC2_TYPE" | jq  '.SpotInstanceRequests[] |  .Status.Code' | tail -n 1 )
            status=$(aws ec2 describe-spot-instance-requests --filters="Name=launch.instance-type,Values=$AWS_EC2_TYPE" | jq  '.SpotInstanceRequests | sort_by(.CreateTime) | .[] | .Status.Code' | tail -n 1)
            if [ "$status" == "\"price-too-low\"" ]
            then
                echo "price-too-low"; # this value is result of function (not message for user), will check later
                return 0
            fi
        fi
    done
}

function createDockerMachine() {
    echo "Attempt to create a docker machine..."
    docker-machine create --driver=amazonec2 --amazonec2-request-spot-instance \
      --amazonec2-keypair-name="$AWS_KEY_PAIR" --amazonec2-ssh-keypath="$AWS_KEY_PATH" \
      --amazonec2-block-duration-minutes=60 \
      --amazonec2-instance-type=$AWS_EC2_TYPE --amazonec2-spot-price=$EC2_PRICE $DOCKER_MACHINE &
}

if [[ "$RUN_ON" = "localhost" ]]; then
  mkdir "$TMP_PATH/pg_nancy_home_${CURRENT_TS}"
  containerHash=$(docker run --name="pg_nancy_${CURRENT_TS}" \
    -v $TMP_PATH/pg_nancy_home_${CURRENT_TS}:/machine_home \
    -dit "postgresmen/postgres-with-stuff:pg${PG_VERSION}" \
  )
  dockerConfig=""

  function cleanup {
    echo "Remove docker container"
    docker container rm -f $containerHash
    echo "Remove temp files..."
    rm -f "$TMP_PATH/conf_$DOCKER_MACHINE.tmp"
    rm -f "$TMP_PATH/ddl_do_$DOCKER_MACHINE.sql"
    rm -f "$TMP_PATH/ddl_undo_$DOCKER_MACHINE.sql"
    rm -f "$TMP_PATH/queries_custom_$DOCKER_MACHINE.sql"
    rm -rf "$TMP_PATH/pg_nancy_home_${CURRENT_TS}"
    echo "Done."
  }
elif [[ "$RUN_ON" = "aws" ]]; then
  ## Get max price from history and apply multiplier
  prices=$(aws --region=us-east-1 ec2 describe-spot-price-history --instance-types $AWS_EC2_TYPE --no-paginate --start-time=$(date +%s) --product-descriptions="Linux/UNIX (Amazon VPC)" --query 'SpotPriceHistory[*].{az:AvailabilityZone, price:SpotPrice}')
  maxprice=$(echo $prices | jq 'max_by(.price) | .price')
  maxprice="${maxprice/\"/}"
  maxprice="${maxprice/\"/}"
  echo "Max price from history: $maxprice"
  multiplier="1.1"
  price=$(echo "$maxprice * $multiplier" | bc -l)
  echo "Increased price: $price"
  EC2_PRICE=$price

  createDockerMachine;
  status=$(waitEC2Ready "docker-machine create" "$DOCKER_MACHINE" 1)
  if [ "$status" == "price-too-low" ]
  then
      echo "Price $price is too low for $AWS_EC2_TYPE instance. Try detect actual."
      corrrectPriceForLastFailedRequest=$(aws ec2 describe-spot-instance-requests --filters="Name=launch.instance-type,Values=$AWS_EC2_TYPE" | jq  '.SpotInstanceRequests[] | select(.Status.Code == "price-too-low") | .Status.Message' | grep -Eo '[0-9]+[.][0-9]+' | tail -n 1 &)
      if [ "$corrrectPriceForLastFailedRequest" != "" ]  &&  [ "$corrrectPriceForLastFailedRequest" != "null" ]
      then
          EC2_PRICE=$corrrectPriceForLastFailedRequest
          #update docker machine name
          CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
          DOCKER_MACHINE="nancy-$CURRENT_TS"
          DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
          #try start docker machine name with new price
          echo "Attempt to create a new docker machine: $DOCKER_MACHINE with price: $EC2_PRICE."
          createDockerMachine;
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

  containerHash=$(docker `docker-machine config $DOCKER_MACHINE` run --name="pg_nancy_${CURRENT_TS}" \
    -v /home/ubuntu:/machine_home -dit "postgresmen/postgres-with-stuff:pg${PG_VERSION}")
  dockerConfig=$(docker-machine config $DOCKER_MACHINE)

  function cleanup {
    cmdout=$(docker-machine rm --force $DOCKER_MACHINE)
    echo "Finished working with machine $DOCKER_MACHINE, termination requested, current status: $cmdout"
    echo "Remove temp files..."
    rm -f "$TMP_PATH/conf_$DOCKER_MACHINE.tmp"
    rm -f "$TMP_PATH/ddl_do_$DOCKER_MACHINE.sql"
    rm -f "$TMP_PATH/ddl_undo_$DOCKER_MACHINE.sql"
    rm -f "$TMP_PATH/queries_custom_$DOCKER_MACHINE.sql"
    echo "Done."
  }
else
  >&2 echo "ASSERT: cannot reach this point"
  exit 1
fi

trap cleanup EXIT

alias docker_exec='docker $dockerConfig exec -i pg_nancy_${CURRENT_TS} '

function copyFile() {
  if [ "$1" != '' ]; then
    if [[ "$1" =~ "s3://" ]]; then # won't work for .s3cfg!
      docker_exec s3cmd sync $1 /machine_home/
    else
      if [ "$RUN_ON" = "localhost" ]; then
        ln $1 "$TMP_PATH/pg_nancy_home_${CURRENT_TS}/" # TODO: option – hard links OR regular `cp`
      elif [ "$RUN_ON" = "aws" ]; then
        docker-machine scp $1 $DOCKER_MACHINE:/home/ubuntu
      else
        >&2 echo "ASSERT: cannot reach this point"
        exit 1
      fi
    fi
  fi
}

[ -v S3_CFG_PATH ] && copyFile $S3_CFG_PATH && docker_exec cp /machine_home/.s3cfg /root/.s3cfg

[ -v DB_DUMP_PATH ] && copyFile $DB_DUMP_PATH
[ -v TARGET_CONFIG ] && copyFile $TARGET_CONFIG
[ -v TARGET_DDL_DO ] && copyFile $TARGET_DDL_DO
[ -v TARGET_DDL_UNDO ] && copyFile $TARGET_DDL_UNDO
[ -v WORKLOAD_CUSTOM_SQL ] && copyFile $WORKLOAD_CUSTOM_SQL
[ -v WORKLOAD_FULL_PATH ] && copyFile $WORKLOAD_FULL_PATH

## Apply machine features
# Dump
sleep 1 # wait for postgres up&running
DB_DUMP_FILENAME=$(basename $DB_DUMP_PATH)
docker_exec bash -c "bzcat /machine_home/$DB_DUMP_FILENAME | psql --set ON_ERROR_STOP=on -U postgres test"
# After init database sql code apply
if ([ -v AFTER_DB_INIT_CODE ] && [ "$AFTER_DB_INIT_CODE" != "" ])
then
    AFTER_DB_INIT_CODE_FILENAME=$(basename $AFTER_DB_INIT_CODE)
    if [[ $AFTER_DB_INIT_CODE =~ "s3://" ]]; then
        docker_exec s3cmd sync $AFTER_DB_INIT_CODE /machine_home/
    else
        docker-machine scp $AFTER_DB_INIT_CODE $DOCKER_MACHINE:/home/ubuntu
    fi
    docker_exec bash -c "psql -U postgres test -E -f /machine_home/$AFTER_DB_INIT_CODE_FILENAME"
fi
# Apply DDL code
echo "Apply DDL SQL code"
if ([ -v TARGET_DDL_DO ] && [ "$TARGET_DDL_DO" != "" ]); then
    TARGET_DDL_DO_FILENAME=$(basename $TARGET_DDL_DO)
    docker_exec bash -c "psql -U postgres test -E -f /machine_home/$TARGET_DDL_DO_FILENAME"
fi
# Apply postgres configuration
echo "Apply postgres conf from /machine_home/conf_$DOCKER_MACHINE.tmp"
if ([ -v TARGET_CONFIG ] && [ "$TARGET_CONFIG" != "" ]); then
    TARGET_CONFIG_FILENAME=$(basename $TARGET_CONFIG)
    docker_exec bash -c "cat /machine_home/$TARGET_CONFIG_FILENAME >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    docker_exec bash -c "sudo /etc/init.d/postgresql restart"
fi
# Clear statistics and log
echo "Execute vacuumdb..."
docker_exec vacuumdb -U postgres test -j $(cat /proc/cpuinfo | grep processor | wc -l) --analyze
docker_exec bash -c "echo '' > /var/log/postgresql/postgresql-$PG_VERSION-main.log"
# Execute workload
echo "Execute workload..."
if [ -v WORKLOAD_FULL_PATH ] && [ "$WORKLOAD_FULL_PATH" != '' ];then
    echo "Execute pgreplay queries..."
    docker_exec psql -U postgres test -c 'create role testuser superuser login;'
    WORKLOAD_FILE_NAME=$(basename $WORKLOAD_FULL_PATH)
    docker_exec bash -c "pgreplay -r -j ./$WORKLOAD_FILE_NAME"
else
    if ([ -v WORKLOAD_CUSTOM_SQL ] && [ "$WORKLOAD_CUSTOM_SQL" != "" ]); then
        WORKLOAD_CUSTOM_FILENAME=$(basename $WORKLOAD_CUSTOM_SQL)
        echo "Execute custom sql queries..."
        docker_exec bash -c "psql -U postgres test -E -f /machine_home/$WORKLOAD_CUSTOM_FILENAME"
    fi
fi

## Get statistics
echo "Prepare JSON log..."
docker_exec bash -c "/root/pgbadger/pgbadger -j $(cat /proc/cpuinfo | grep processor | wc -l) --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' /var/log/postgresql/* -f stderr -o /machine_home/$ARTIFACTS_FILENAME.json"
echo "Upload JSON log..."

if [[ $ARTIFACTS_DESTINATION =~ "s3://" ]]; then
    docker_exec s3cmd put /machine_home/$ARTIFACTS_FILENAME.json $ARTIFACTS_DESTINATION/
else
    if [ "$RUN_ON" = "localhost" ]; then
      cp "$TMP_PATH/pg_nancy_home_${CURRENT_TS}/"$ARTIFACTS_FILENAME.json $ARTIFACTS_DESTINATION/
    elif [ "$RUN_ON" = "aws" ]; then
      docker-machine scp /machine_home/$ARTIFACTS_FILENAME.json $DOCKER_MACHINE:/home/ubuntu
    else
      >&2 echo "ASSERT: cannot reach this point"
      exit 1
    fi
fi

echo "Apply DDL undo SQL code from /machine_home/ddl_undo_$DOCKER_MACHINE.sql"
if ([ -v TARGET_DDL_UNDO ] && [ "$TARGET_DDL_UNDO" != "" ]); then
    TARGET_DDL_UNDO_FILENAME=$(basename $TARGET_DDL_UNDO)
    docker_exec bash -c "psql -U postgres test -E -f /machine_home/$TARGET_DDL_UNDO_FILENAME"
fi

echo -e "Run done!"
echo -e "Result log: $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME.json"
echo -e "-------------------------------------------"
echo -e "Summary:"
echo -e "  Queries number:\t\t" $(cat $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME.json | jq '.overall_stat.queries_number')
echo -e "  Queries duration:\t\t" $(cat $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME.json | jq '.overall_stat.queries_duration') " ms"
echo -e "  Errors number:\t\t" $(cat $ARTIFACTS_DESTINATION/$ARTIFACTS_FILENAME.json | jq '.overall_stat.errors_number')
echo -e "-------------------------------------------"

sleep $DEBUG_TIMEOUT

echo Bye!
