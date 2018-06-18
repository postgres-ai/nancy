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
    --aws-ec2-type )
        AWS_EC2_TYPE="$2"; shift 2 ;;
    --pg-version )
        PG_VERSION="$2"; shift 2 ;;
    --pg-config )
        PG_CONFIG="$2"; shift 2 ;;
    --db-prepared-snapshot )
        DB_PREPARED_SNAPSHOT="$2"; shift 2 ;;
    --db-dump-path )
        DB_DUMP_PATH="$2"; shift 2 ;;
    --after-db-init-code )
        AFTER_DB_INIT_CODE="$2"; shift 2 ;;
    --workload-full-path )
        WORKLOAD_FULL_PATH="$2"; shift 2 ;;
    --workload-basis-path )
        WORKLOAD_BASIS_PATH="$2"; shift 2 ;;
    --workload-custom-sql )
        WORKLOAD_CUSTOM_SQL="$2"; shift 2 ;;
    --workload-replay-speed )
        WORKLOAD_REPLAY_SPEED="$2"; shift 2 ;;
    --target-ddl-do )
        TARGET_DDL_DO="$2"; shift 2 ;;
    --target-ddl-undo )
        TARGET_DDL_UNDO="$2"; shift 2 ;;
    --clean-run-only )
        CLEAN_RUN_ONLY=1; shift 1 ;;
    --target-config )
        TARGET_CONFIG="$2"; shift 2 ;;
    --artifacts-destination )
        ARTIFACTS_DESTINATION="$2"; shift 2 ;;

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

if [ $DEBUG -eq 1 ]
then
    echo "debug: ${DEBUG}"
    echo "aws_ec2_type: ${AWS_EC2_TYPE}"
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
    echo "clean_run_only: $CLEAN_RUN_ONLY"
    echo "target_config: $TARGET_CONFIG"
    echo "artifacts_destination: $ARTIFACTS_DESTINATION"
    echo "aws-key-pair: $AWS_KEY_PAIR"
    echo "aws-key-path: $AWS_KEY_PATH"
    echo "s3-cfg-path: $S3_CFG_PATH"
    echo "tmp-path: $TMP_PATH"
    echo "after-db-init-code: $AFTER_DB_INIT_CODE"
fi

## Check params
function checkParams() {
    if ([ ! -v AWS_KEY_PAIR ] || [ ! -v AWS_KEY_PATH ])
    then
        >&2 echo "ERROR: AWS keys not given."
        exit 1
    fi

    if [ ! -v AWS_EC2_TYPE ]
    then
        >&2 echo "ERROR: Instance type not given."
        exit 1
    fi

    if [ ! -v PG_VERSION ]
    then
        >&2 echo "WARNING: Postgres version not given. Will used 9.6."
        PG_VERSION="9.6"
    fi

    if [ ! -v TMP_PATH ]
    then
        TMP_PATH="/var/tmp/nancy_run"
        >&2 echo "WARNING: Temp path not given. Will used $TMP_PATH"
    fi
    #make tmp path if not found
    [ ! -d $TMP_PATH ] && mkdir $TMP_PATH

    if [ ! -v S3_CFG_PATH ]
    then
        >&2 echo "WARNING: S3 config file path not given. Will used ~/.s3cfg"
        S3_CFG_PATH="~/.s3cfg"
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

    if (([ -v TARGET_DDL_DO ] || [ -v TARGET_CONFIG ]) && [ -v CLEAN_RUN_ONLY ])
    then
        >&2 echo "ERROR: Cannot be execute 'target run' and 'clean run' at the same time."
        exit 1;
    fi

    if (([ ! -v TARGET_DDL_UNDO ] && [ -v TARGET_DDL_DO ]) || ([ ! -v TARGET_DDL_DO ] && [ -v TARGET_DDL_UNDO ]))
    then
        >&2 echo "ERROR: DDL code must have do and undo part."
        exit 1;
    fi

    if [ ! -v ARTIFACTS_DESTINATION ]
    then
        >&2 echo "WARNING: Artifacts destination not given. Will used ./"
        ARTIFACTS_DESTINATION="."
    fi
}

checkParams;

exit 1

set -ueo pipefail
[ $DEBUG -eq 1 ] && set -ueox pipefail # to debug

## Docker tools
function waitDockerReady() {
    cmd=$1
    machine=$2
    checkPrice=$3
    while true; do
        sleep 5; STOP=1
        ps ax | grep "$cmd" | grep "$machine" >/dev/null && STOP=0
        ((STOP==1)) && return 0
        if [ $checkPrice -eq 1 ]
        then
            status=$(aws ec2 describe-spot-instance-requests --filters="Name=launch.instance-type,Values=$AWS_EC2_TYPE" | jq  '.SpotInstanceRequests[] | .Status.Code' | tail -n 1 )
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
status=$(waitDockerReady "docker-machine create" "$DOCKER_MACHINE" 1)
if [ "$status" == "price-too-low" ]
then
    echo "Price $price is too low for $AWS_EC2_TYPE instance. Try detect actual."
    corrrectPriceForLastFailedRequest=$(aws ec2 describe-spot-instance-requests --filters="Name=launch.instance-type,Values=$AWS_EC2_TYPE" | jq  '.SpotInstanceRequests[] | select(.Status.Code == "price-too-low") | .Status.Message' | grep -Eo '[0-9]+[.][0-9]+' | tail -n 1 &)
    if ([ "$corrrectPriceForLastFailedRequest" != "" ]  &&  [ "$corrrectPriceForLastFailedRequest" != "null" ])
    then
        EC2_PRICE=$corrrectPriceForLastFailedRequest
        #update docker machine name
        CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
        DOCKER_MACHINE="nancy-$CURRENT_TS"
        DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
        #try start docker machine name with new price
        echo "Attempt to create a new docker machine: $DOCKER_MACHINE with price: $EC2_PRICE."
        createDockerMachine;
        waitDockerReady "docker-machine create" "$DOCKER_MACHINE" 0;
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

containerHash=$(docker `docker-machine config $DOCKER_MACHINE` run --name="pg_nancy" \
  -v /home/ubuntu:/machine_home -dit "950603059350.dkr.ecr.us-east-1.amazonaws.com/nancy:postgres${PG_VERSION}")
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
trap cleanup EXIT

## Prepare conf, queries and dump files
if ([ "$TARGET_CONFIG" != "" ]  &&  [ "$TARGET_CONFIG" != "null" ])
then
    echo "TARGET_CONFIG is not empty: $TARGET_CONFIG"
    echo "$TARGET_CONFIG" > $TMP_PATH/conf_$DOCKER_MACHINE.tmp
fi

if ([ -v TARGET_DDL_DO ] && [ "$TARGET_DDL_DO" != "" ])
then
    echo "TARGET_DDL_DO is not empty: $TARGET_DDL_DO"
    echo "$TARGET_DDL_DO" > $TMP_PATH/ddl_do_$DOCKER_MACHINE.sql
fi

if ([ -v TARGET_DDL_UNDO ] && [ "$TARGET_DDL_UNDO" != "" ])
then
    echo "TARGET_DDL_UNDO is not empty: $TARGET_DDL_UNDO"
    echo "$TARGET_DDL_UNDO" > $TMP_PATH/ddl_undo_$DOCKER_MACHINE.sql
fi

if ([ -v WORKLOAD_CUSTOM_SQL ] && [ "$WORKLOAD_CUSTOM_SQL" != "" ])
then
    echo "WORKLOAD_CUSTOM_SQL is not empty: $WORKLOAD_CUSTOM_SQL"
    echo "$WORKLOAD_CUSTOM_SQL" > $TMP_PATH/queries_custom_$DOCKER_MACHINE.sql
fi

shopt -s expand_aliases
alias sshdo='docker $dockerConfig exec -i pg_nancy '

## Copy data to docker machine
docker-machine scp $S3_CFG_PATH $DOCKER_MACHINE:/home/ubuntu
sshdo cp /machine_home/.s3cfg /root/.s3cfg
sshdo s3cmd sync $DB_DUMP_PATH ./
if [ -f "$TMP_PATH/conf_$DOCKER_MACHINE.tmp" ]; then
    docker-machine scp $TMP_PATH/conf_$DOCKER_MACHINE.tmp $DOCKER_MACHINE:/home/ubuntu
fi
if [ -f "$TMP_PATH/ddl_do_$DOCKER_MACHINE.sql" ]; then
    docker-machine scp $TMP_PATH/ddl_do_$DOCKER_MACHINE.sql $DOCKER_MACHINE:/home/ubuntu
fi
if [ -f "$TMP_PATH/ddl_undo_$DOCKER_MACHINE.sql" ]; then
    docker-machine scp $TMP_PATH/ddl_undo_$DOCKER_MACHINE.sql $DOCKER_MACHINE:/home/ubuntu
fi
if [ -f "$TMP_PATH/queries_custom_$DOCKER_MACHINE.sql" ]; then
    docker-machine scp $TMP_PATH/queries_custom_$DOCKER_MACHINE.sql $DOCKER_MACHINE:/home/ubuntu
fi
if ([ "$WORKLOAD_FULL_PATH" != "" ]  &&  [ "$WORKLOAD_FULL_PATH" != "null" ])
then
    sshdo s3cmd sync $WORKLOAD_FULL_PATH ./
fi


## Apply machine features
# Dump
DB_DUMP_FILENAME=$(basename $DB_DUMP_PATH)
sshdo bash -c "bzcat ./$DB_DUMP_FILENAME | psql --set ON_ERROR_STOP=on -U postgres test"
# After init database sql code apply
if ([ -v AFTER_DB_INIT_CODE ] && [ "$AFTER_DB_INIT_CODE" != "" ])
then
    sshdo psql -U postgres test -c "$AFTER_DB_INIT_CODE"
fi
# Apply DDL code
echo "Apply DDL SQL code from /machine_home/ddl_do_$DOCKER_MACHINE.sql"
if [ -f "$TMP_PATH/ddl_do_$DOCKER_MACHINE.sql" ]; then
    sshdo bash -c "psql -U postgres test -E -f /machine_home/ddl_do_$DOCKER_MACHINE.sql"
fi
# Apply postgres configuration
echo "Apply postgres conf from /machine_home/conf_$DOCKER_MACHINE.tmp"
if [ -f "$TMP_PATH/conf_$DOCKER_MACHINE.tmp" ]; then
    sshdo bash -c "cat /machine_home/conf_$DOCKER_MACHINE.tmp >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    sshdo bash -c "sudo /etc/init.d/postgresql restart"
fi
# Clear statistics and log
echo "Execute vacuumdb..."
sshdo vacuumdb -U postgres test -j $(cat /proc/cpuinfo | grep processor | wc -l) --analyze
sshdo bash -c "echo '' > /var/log/postgresql/postgresql-$PG_VERSION-main.log"
# Execute workload
echo "Execute workload..."
if ([ "$WORKLOAD_FULL_PATH" != "" ]  &&  [ "$WORKLOAD_FULL_PATH" != "null" ])
then
    echo "Execute pgreplay queries..."
    sshdo psql -U postgres test -c 'create role testuser superuser login;'
    WORKLOAD_FILE_NAME=$(basename $WORKLOAD_FULL_PATH)
    sshdo bash -c "pgreplay -r -j ./$WORKLOAD_FILE_NAME"
else
    if [ -f "$TMP_PATH/queries_custom_$DOCKER_MACHINE.sql" ]; then
        echo "Execute custom sql queries..."
        sshdo bash -c "psql -U postgres test -E -f /machine_home/queries_custom_$DOCKER_MACHINE.sql"
    fi
fi

## Get statistics
sshdo bash -c "git clone https://github.com/dmius/pgbadger.git /machine_home/pgbadger"
echo "Prepare JSON log..."
sshdo bash -c "/machine_home/pgbadger/pgbadger -j $(cat /proc/cpuinfo | grep processor | wc -l) --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' /var/log/postgresql/* -f stderr -o /$DOCKER_MACHINE.json"
echo "Upload JSON log..."

if [[ $ARTIFACTS_DESTINATION =~ "s3://" ]]; then
    sshdo s3cmd put /$DOCKER_MACHINE.json $ARTIFACTS_DESTINATION/
else
    sshdo cp /$DOCKER_MACHINE.json /machine_home/
    docker-machine scp $DOCKER_MACHINE:/home/ubuntu/$DOCKER_MACHINE.json  $ARTIFACTS_DESTINATION/
fi

sshdo s3cmd put /$DOCKER_MACHINE.json $ARTIFACTS_DESTINATION/

echo "Apply DDL undo SQL code from /machine_home/ddl_undo_$DOCKER_MACHINE.sql"
if [ -f "$TMP_PATH/ddl_undo_$DOCKER_MACHINE.sql" ]; then
    sshdo bash -c "psql -U postgres test -E -f /machine_home/ddl_undo_$DOCKER_MACHINE.sql"
fi

sleep $DEBUG_TIMEOUT

echo Bye!
