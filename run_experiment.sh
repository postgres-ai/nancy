#!/bin/bash
TOKEN=$JWT_TOKEN
EXPERIMENT_ID=$EXP_ID
EXPERIMENT_RUN_ID=$EXP_RUN_ID
REST_URL="http://dev.imgdata.ru:9508"


function updateExperimentRunStatus() {
    status=$1
    res=$(wget --quiet \
      --method PATCH \
      --header "authorization: Bearer $TOKEN" \
      --header 'content-type: application/x-www-form-urlencoded' \
      --header 'cache-control: no-cache' \
      --header 'postman-token: 39be31c6-55ba-6ca1-fd33-8f02f65b278f' \
      --body-data "status=$status&status_changed=now()" \
      --output-document \
      - "$REST_URL/experiment_run?id=eq.$EXPERIMENT_RUN_ID")
}

expData=$(wget --quiet \
  --method GET \
  --header "authorization: Bearer $TOKEN" \
  --header 'cache-control: no-cache' \
  --header 'postman-token: 8237b87c-e2b5-f87c-6946-81bb01d01261' \
  --output-document \
  - "$REST_URL/experiment_runs?experiment_run_id=eq.$EXPERIMENT_RUN_ID")

queriesCustom=$(echo $expData | jq -r '.[0].queries_custom')
queriesUrl=$(echo $expData | jq -r '.[0].queries_pgreplay')
queriesFileName=$(basename $queriesUrl)
pgVersion=$(echo $expData | jq -r '.[0].postgres_version')
projectName=$(echo $expData | jq -r '.[0].project_name')
confChanges=$(echo $expData | jq -r '.[0].change."postgresql.conf"')
ddlChanges=$(echo $expData | jq -r '.[0].change."ddl"')
dumpUrl=$(echo $expData | jq -r '.[0].dump_url')
dumpFileName=$(basename $dumpUrl)
storageDir=$(dirname $dumpUrl)
instanceType=$(echo $expData | jq -r '.[0].instance_type')

if [ "$confChanges" == "9.5" ] 
then
    pgVersion='9.6'
fi
pgVersion='9.6'

echo "Queries 1: '$queriesCustom'"
echo "Queries 2: $queriesUrl"
echo "Queries 3: $queriesFileName"
echo "PG Ver:  $pgVersion Fixed"
echo "ProjectName:  $projectName"
echo "Conf changes: $confChanges"
echo "DDL changes: $ddlChanges"
echo "dumpUrl: $dumpUrl"
echo "dumpFilename: $dumpFileName"
echo "dumpFlleDir: $storageDir"
echo "instanceType: $instanceType"

updateExperimentRunStatus "in_progress";

#PG_VERSION="${PG_VERSION:-10}"
PG_VERSION="${PG_VERSION:-$pgVersion}"
#PROJECT="${PROJECT:-postila_ru}"
PROJECT="${PROJECT:-$projectName}"
CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
DOCKER_MACHINE="${DOCKER_MACHINE:-nancy-$PROJECT-$CURRENT_TS-$EXPERIMENT_ID-$EXPERIMENT_RUN_ID}"
DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
EC2_TYPE="${EC2_TYPE:-r4.large}"
EC2_PRICE="${EC2_PRICE:-0.0315}"
EC2_KEY_PAIR=${EC2_KEY_PAIR:-awskey}
EC2_KEY_PATH=${EC2_KEY_PATH:-/Users/nikolay/.ssh/awskey.pem}
S3_BUCKET="${S3_BUCKET:-p-dumps}"

CONTAINER_PG_VER=`php -r "print str_replace('.', '', '$PG_VERSION');"`

if [ "$confChanges" != "null" && "$confChanges" != "" ]
then
    echo "$confChanges" > /tmp/conf_$DOCKER_MACHINE.tmp
fi
if [ "$ddlChanges" != "null" &&  "$ddlChanges" != "" ]
then
    echo "$ddlChanges" > /tmp/ddl_$DOCKER_MACHINE.sql
fi
if [ "$queriesCustom" != "null" && "$queriesCustom" != "" ]
then
    echo "$queriesCustom" > /tmp/queries_custom_$DOCKER_MACHINE.sql
fi

set -ueo pipefail
set -ueox pipefail # to debug

docker-machine create --driver=amazonec2 --amazonec2-request-spot-instance \
  --amazonec2-keypair-name="$EC2_KEY_PAIR" --amazonec2-ssh-keypath="$EC2_KEY_PATH" \
  --amazonec2-instance-type=$EC2_TYPE --amazonec2-spot-price=$EC2_PRICE $DOCKER_MACHINE

eval $(docker-machine env $DOCKER_MACHINE)

containerHash=$(docker `docker-machine config $DOCKER_MACHINE` run --name="pg_nancy" \
  -v /home/ubuntu:/machine_home -dit "950603059350.dkr.ecr.us-east-1.amazonaws.com/nancy:pg${CONTAINER_PG_VER}_$EC2_TYPE")
dockerConfig=$(docker-machine config $DOCKER_MACHINE)

function cleanup {
  cmdout=$(docker-machine rm --force $DOCKER_MACHINE)
  echo "Finished working with machine $DOCKER_MACHINE, termination requested, current status: $cmdout"
  echo "Remove temp files..."
  if [ -f "/tmp/conf_$DOCKER_MACHINE.tmp" ]; then
    rm /tmp/conf_$DOCKER_MACHINE.tmp
  fi
  if [ -f "/tmp/ddl_$DOCKER_MACHINE.sql" ]; then
    rm /tmp/ddl_$DOCKER_MACHINE.sql
  fi
  if [ -f "/tmp/queries_custom_$DOCKER_MACHINE.sql" ]; then
    rm /tmp/queries_custom_$DOCKER_MACHINE.sql
  fi
}
trap cleanup EXIT

shopt -s expand_aliases
alias sshdo='docker $dockerConfig exec -i pg_nancy '

docker-machine scp ~/.s3cfg $DOCKER_MACHINE:/home/ubuntu
sshdo cp /machine_home/.s3cfg /root/.s3cfg

if [ -f "/tmp/conf_$DOCKER_MACHINE.tmp" ]; then
    docker-machine scp /tmp/conf_$DOCKER_MACHINE.tmp $DOCKER_MACHINE:/home/ubuntu
fi
if [ -f "/tmp/ddl_$DOCKER_MACHINE.sql" ]; then
    docker-machine scp /tmp/ddl_$DOCKER_MACHINE.sql $DOCKER_MACHINE:/home/ubuntu
fi
if [ -f "/tmp/queries_custom_$DOCKER_MACHINE.sql" ]; then
    docker-machine scp /tmp/queries_custom_$DOCKER_MACHINE.sql $DOCKER_MACHINE:/home/ubuntu
fi

updateExperimentRunStatus "aws_ready";

sshdo s3cmd sync $dumpUrl ./
if [ "$queriesUrl" != "null" ]
then
    sshdo s3cmd sync $queriesUrl ./
fi

updateExperimentRunStatus "aws_init_env";

sshdo bash -c "git clone https://github.com/NikolayS/pgbadger.git /machine_home/pgbadger"

# Apply conf here
sshdo bash -c "bzcat ./$dumpFileName | psql --set ON_ERROR_STOP=on -U postgres test"

sshdo psql -U postgres test -c 'refresh materialized view a__news_daily_90days_denominated;' # remove me later

if [ -f "/tmp/ddl_$DOCKER_MACHINE.sql" ]; then
    sshdo bash -c "psql -U postgres test -E -f /machine_home/ddl_$DOCKER_MACHINE.sql"
fi

if [ -f "/tmp/conf_$DOCKER_MACHINE.tmp" ]; then
    sshdo bash -c "cat /machine_home/conf_$DOCKER_MACHINE.tmp >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
    sshdo bash -c "sudo /etc/init.d/postgresql restart"
fi

sshdo vacuumdb -U postgres test -j 10 --analyze

updateExperimentRunStatus "aws_start_test";

sshdo bash -c "echo '' > /var/log/postgresql/postgresql-$PG_VERSION-main.log"

if [ -f "/tmp/queries_custom_$DOCKER_MACHINE.sql" ]; then
    echo "USE CUSTOM QUERIES"
    sshdo bash -c "psql -U postgres test -E -f /machine_home/queries_custom_$DOCKER_MACHINE.sql"
else 
    echo "USE REPLAY QUERIES"
    sshdo bash -c "psql -U postgres test -E -f ./$queriesFileName"
fi

updateExperimentRunStatus "aws_analyze";
sshdo bash -c "/machine_home/pgbadger/pgbadger -j 4 --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' /var/log/postgresql/* -f stderr -o /${PROJECT}_experiment_${CURRENT_TS}_${EXPERIMENT_ID}_${EXPERIMENT_RUN_ID}.json"

sshdo s3cmd put /${PROJECT}_experiment_${CURRENT_TS}_${EXPERIMENT_ID}_${EXPERIMENT_RUN_ID}.json $storageDir/

sshdo sudo apt-get -y install jq

sshdo s3cmd sync s3://p-dumps/tools/logloader.php ./
sshdo s3cmd sync s3://p-dumps/tools/config.local.php ./
sshdo php ./logloader.php --log=/${PROJECT}_experiment_${CURRENT_TS}_${EXPERIMENT_ID}_${EXPERIMENT_RUN_ID}.json --experiment=$EXPERIMENT_ID --exprun=$EXPERIMENT_RUN_ID --token=$TOKEN

updateExperimentRunStatus "done";

sleep 600

echo Bye!
