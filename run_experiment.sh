#!/bin/bash
PG_VERSION="${PG_VERSION:-10}"
PROJECT="${PROJECT:-postila_ru}"
CURRENT_TS=$(date +%Y%m%d_%H%M%S_%Z)
DOCKER_MACHINE="${DOCKER_MACHINE:-nancy-$PROJECT-$CURRENT_TS}"
DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
EC2_TYPE="${EC2_TYPE:-r4.large}"
EC2_PRICE="${EC2_PRICE:-0.0315}"
EC2_KEY_PAIR=${EC2_KEY_PAIR:-awskey}
EC2_KEY_PATH=${EC2_KEY_PATH:-/Users/nikolay/.ssh/awskey.pem}
S3_BUCKET="${S3_BUCKET:-p-dumps}"

TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MiwibmFtZSI6ImRldl9wb3N0aWxhX3J1IiwiY3JlYXRlZCI6IjIwMTgtMDQtMjhUMTE6MTk6NTcuODU3ODU0KzAwOjAwIiwicm9sZSI6ImFwaXVzZXIifQ.z504wiWz8qVY1WaWdyW8WbuDnCxAFbjToqqOYFMnz5w  # TODO: parametrize!
EXPERIMENT_ID=1 # TODO: parametrize!
EXPERIMENT_STEP=0 # TODO: parametrize!

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
alias sshdo='docker $dockerConfig exec -it pg_nancy '

docker-machine scp ~/.s3cfg $DOCKER_MACHINE:/home/ubuntu
sshdo cp /machine_home/.s3cfg /root/.s3cfg

sshdo s3cmd sync s3://p-dumps/dev.imgdata.ru/postila_ru.sql-20180503.bz2 ./ # TODO: parametrize!
sshdo s3cmd sync s3://p-dumps/dev.imgdata.ru/queries.sql ./ # TODO: parametrize!

sshdo bash -c "bzcat ./postila_ru.sql-20180503.bz2 | psql --set ON_ERROR_STOP=on -U postgres test" # TODO: parametrize!

sshdo psql -U postgres test -c 'refresh materialized view a__news_daily_90days_denominated;' # remove me later

sshdo vacuumdb -U postgres test -j 10 --analyze

sshdo bash -c "psql -U postgres test -E -f ./queries.sql"

sshdo bash -c "pgbadger -j 4 --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' /var/log/postgresql/* -f stderr -o /${PROJECT}_experiment_${CURRENT_TS}.json"

sshdo s3cmd put /${PROJECT}_experiment_${CURRENT_TS}.json s3://p-dumps/dev.imgdata.ru/

sshdo sudo apt -y update
sshdo sudo apt -y install php7.0
sshdo sudo apt -y install php7.0-cli php7.0-curl
sshdo php --version
sshdo sudo apt-get -y install jq
sshdo s3cmd sync s3://p-dumps/tools/logloader.php ./
sshdo s3cmd sync s3://p-dumps/tools/config.local.php ./
sshdo php ./logloader.php --log=/${PROJECT}_experiment_${CURRENT_TS}.json --experiment=$EXPERIMENT_ID --expstep=$EXPERIMENT_STEP --token=$TOKEN


sleep 600

echo Bye!
