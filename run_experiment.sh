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
pgVersion=$(echo $expData | jq -r '.[0].engine_version')
projectName=$(echo $expData | jq -r '.[0].project_name')
changes=$(echo $expData | jq -r '.[0].change."postgresql.conf"')
dumpUrl=$(echo $expData | jq -r '.[0].dump_url')
dumpFileName=$(basename $dumpUrl)
storageDir=$(dirname $dumpUrl)
databaseVersion=$(echo $expData | jq -r '.[0].database_version')

echo "Queries 1: $queriesCustom"
echo "Queries 2: $queriesUrl"
echo "Queries 3: $queriesFileName"
echo "PG Ver:  $pgVersion"
echo "ProjectName:  $projectName"
echo "changes: $changes"
echo "dumpUrl: $dumpUrl"
echo "dumpFilename: $dumpFileName"
echo "dumpFlleDir: $storageDir"
echo "databaseVersion: $databaseVersion"

updateExperimentRunStatus "aws_init";

#PG_VERSION="${PG_VERSION:-10}"
PG_VERSION="${PG_VERSION:-$pgVersion}"
#PROJECT="${PROJECT:-postila_ru}"
PROJECT="${PROJECT:-$projectName}"
CURRENT_TS=$(date +%Y%m%d_%H%M%S%N_%Z)
DOCKER_MACHINE="${DOCKER_MACHINE:-nancy-$PROJECT-$CURRENT_TS}"
DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
EC2_TYPE="${EC2_TYPE:-r4.large}"
EC2_PRICE="${EC2_PRICE:-0.0315}"
EC2_KEY_PAIR=${EC2_KEY_PAIR:-awskey}
EC2_KEY_PATH=${EC2_KEY_PATH:-/Users/nikolay/.ssh/awskey.pem}
S3_BUCKET="${S3_BUCKET:-p-dumps}"

set -ueo pipefail
set -ueox pipefail # to debug

docker-machine create --driver=amazonec2 --amazonec2-request-spot-instance \
  --amazonec2-keypair-name="$EC2_KEY_PAIR" --amazonec2-ssh-keypath="$EC2_KEY_PATH" \
  --amazonec2-instance-type=$EC2_TYPE --amazonec2-spot-price=$EC2_PRICE $DOCKER_MACHINE

eval $(docker-machine env $DOCKER_MACHINE)

containerHash=$(docker `docker-machine config $DOCKER_MACHINE` run --name="pg_nancy" \
  -v /home/ubuntu:/machine_home -dit "950603059350.dkr.ecr.us-east-1.amazonaws.com/nancy:pg96_$EC2_TYPE")
dockerConfig=$(docker-machine config $DOCKER_MACHINE)

function cleanup {
  cmdout=$(docker-machine rm --force $DOCKER_MACHINE)
  echo "Finished working with machine $DOCKER_MACHINE, termination requested, current status: $cmdout"
}
trap cleanup EXIT

shopt -s expand_aliases
alias sshdo='docker $dockerConfig exec -i pg_nancy '

docker-machine scp ~/.s3cfg $DOCKER_MACHINE:/home/ubuntu
sshdo cp /machine_home/.s3cfg /root/.s3cfg

updateExperimentRunStatus "aws_ready";

sshdo s3cmd sync $dumpUrl ./
sshdo s3cmd sync $queriesUrl ./

updateExperimentRunStatus "aws_init_env";

sshdo bash -c "bzcat ./$dumpFileName | psql --set ON_ERROR_STOP=on -U postgres test"

sshdo psql -U postgres test -c 'refresh materialized view a__news_daily_90days_denominated;' # remove me later

sshdo vacuumdb -U postgres test -j 10 --analyze

updateExperimentRunStatus "aws_start_test";
sshdo bash -c "psql -U postgres test -E -f ./$queriesFileName"

updateExperimentRunStatus "aws_analyze";
sshdo bash -c "pgbadger -j 4 --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' /var/log/postgresql/* -f stderr -o /${PROJECT}_experiment_${CURRENT_TS}.json"

sshdo s3cmd put /${PROJECT}_experiment_${CURRENT_TS}.json $storageDir

sshdo sudo apt-get -y install jq

sshdo s3cmd sync s3://p-dumps/tools/logloader.php ./
sshdo s3cmd sync s3://p-dumps/tools/config.local.php ./
sshdo php ./logloader.php --log=/${PROJECT}_experiment_${CURRENT_TS}.json --experiment=$EXPERIMENT_ID --expstep=$EXPERIMENT_RUN_ID --token=$TOKEN

updateExperimentRunStatus "done";

sleep 600

echo Bye!
