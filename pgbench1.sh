#!/bin/bash

USAGE="pgbench1 -t xxxxx -e 0 -s 1 -k xxx -c xxx"

while getopts ht:e:s:k:c: OPT; do
    case "$OPT" in
        t)
            TOKEN=$OPTARG
            ;;
        e)
            EXPERIMENT_ID=$OPTARG
            ;;
        s)
            EXPERIMENT_STEP=$OPTARG
            ;;
        k)
            S3_KEY=$OPTARG
            ;;
        c)
            S3_SECRET=$OPTARG
            ;;
        \?)
            # getopts вернул ошибку
            echo $USAGE
            exit 1
            ;;
    esac
done

echo "Token: $TOKEN"
echo 'Experiment id: ' $EXPERIMENT_ID
echo 'Experiment step: ' $EXPERIMENT_STEP
echo 'S3 Key: '  $S3_KEY
echo 'S3 Secret' $S3_SECRET
 
define(){ IFS='\n' read -r -d '' ${1} || true; }

set -ueo pipefail
set -ueox pipefail # to debug

instanceIdDefined="${instanceIdDefined:-}"
pgVers="${pgVers:-9.6}"
S3_BUCKET="${S3_BUCKET:-p-dumps}"
ec2Type="${ec2Type:-r3.large}"
ec2Price="${ec2Price:-0.035}"
n="${n:-50}"
s="${s:-100}"
increment="${increment:-50}"
duration="${duration:-30}"
pgConfig=$(cat "config/$ec2Type")

if [ -z "$pgConfig" ]
then
  echo "ERROR: cannot find Postgres config for $ec2Type" 1>&2
  exit 1
fi

d=$(date)
echo "*******************************************************"
echo "TEST:                   pgbench                        "
echo "Current date/time:      $d"
echo "EC2 node type:          $ "
echo "Postgres major version: $pgVers"
echo "*******************************************************"


define ec2Opts <<EC2OPT
  {
    "MarketType": "spot",
    "SpotOptions": {
      "MaxPrice": "$ec2Price",
      "SpotInstanceType": "one-time",
      "InstanceInterruptionBehavior": "terminate"
    }
  }
EC2OPT

if [ -z "$instanceIdDefined" ]
then
  cmdout=$(aws ec2 run-instances --image-id "ami-9d751ee7" --count 1 \
    --instance-type "$ec2Type"  \
    --instance-market-options "$ec2Opts" \
    --security-group-ids "sg-069a1372" \
    --block-device-mappings "[{\"DeviceName\": \"/dev/sda1\",\"Ebs\":{\"VolumeSize\":300}}]" \
    --key-name awskey2)

  instanceId=$(echo $cmdout | jq -r '.Instances[0].InstanceId')
else
  instanceId="$instanceIdDefined"
fi

function cleanup {
  cmdout=$(aws ec2 terminate-instances --instance-ids "$instanceId" | jq '.TerminatingInstances[0].CurrentState.Name')
  echo "Finished working with instance $instanceId, termination requested, current status: $cmdout"
}
trap cleanup EXIT


instanceState=$(echo $cmdout | jq -r '.Instances[0].State.Code')

echo "Instance requested, id: $instanceId, state code: $instanceState"

while true; do
  status=$(aws ec2 describe-instance-status --instance-ids "$instanceId" | jq -r '.InstanceStatuses[0].SystemStatus.Status')
  if [[ "$status" == "ok" ]]; then
    break
  fi
  echo "Status is $status, waiting 30 seconds…"
  sleep 30
done

instanceIP=$(aws ec2 describe-instances --instance-ids "$instanceId" | jq -r '.Reservations[0].Instances[0].PublicIpAddress')
echo "Public IP: $instanceIP"

shopt -s expand_aliases
alias sshdo='ssh -i ~/.ssh/awskey2.pem -o "StrictHostKeyChecking no" "ubuntu@$instanceIP"'

define upd <<CONF
\set aid random(1, 100000 * :scale)
\set bid random(1, 1 * :scale)
\set tid random(1, 10 * :scale)
\set delta random(-5000, 5000)

begin;
UPDATE pgbench_tellers SET tbalance = tbalance + :delta WHERE tid = :tid;
end;
CONF

define ins <<CONF
\set aid random(1, 100000 * :scale)
\set bid random(1, 1 * :scale)
\set tid random(1, 10 * :scale)
\set delta random(-5000, 5000)

begin;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);
end;
CONF

sshdo "echo \"$ins\" > /tmp/ins.bench"
sshdo "echo \"$upd\" > /tmp/upd.bench"

#sshdo "tmux new-session -d -s prep"
#sshdo "tmux send -t prep 'sudo mkfs -t ext4 /dev/xvdb && sudo mkdir /var/lib/postgresql && sudo mount /dev/xvdb /var/lib/postgresql'"
#sshdo "tmux send-keys -t prep Enter"
sshdo "sudo mkdir /postgresql && sudo ln -s /postgresql /var/lib/postgresql"
sshdo "sudo mkdir /dev/postgresql && sudo ln -s /dev/postgresql /var/lib/postgresql"

sshdo "sudo sh -c 'echo \"deb http://apt.postgresql.org/pub/repos/apt/ \`lsb_release -cs\`-pgdg main\" >> /etc/apt/sources.list.d/pgdg.list'"
sshdo 'wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -'
sshdo 'sudo apt-get update >/dev/null'
sshdo "sudo apt-get install -y postgresql-$pgVers"

sshdo "echo \"$pgConfig\" >/tmp/111 && sudo sh -c 'cat /tmp/111 >> /etc/postgresql/$pgVers/main/postgresql.conf'"

    #For Postila database
    sshdo "sudo apt-get install s3cmd"
    sshdo "echo '[default]' > ~/.s3cfg"
    sshdo "echo 'access_key = $S3_KEY' >> ~/.s3cfg"
    sshdo "echo 'secret_key = $S3_SECRET' >> ~/.s3cfg"
    sshdo "echo 'region = us-east-1' >> ~/.s3cfg"
    
    
    sshdo "sudo apt-get install -y npm postgresql-contrib-$pgVers postgresql-plpython-$pgVers postgresql-$pgVers-plsh postgresql-server-dev-$pgVers"
    sshdo "sudo apt-get install postgresql-$pgVers-rum"
    sshdo "s3cmd sync s3://p-dumps/dev.imgdata.ru/tsearch_data ~/"
    sshdo "sudo cp ~/tsearch_data/* /usr/share/postgresql/$pgVers/tsearch_data"
    #sshdo "sudo sh -c 'echo \"postila.service_copier = 'https://copierdev.postila.ru'\" >> /etc/postgresql/10/main/postgresql.conf'"
    # sshdo "sudo sh -c 'echo \"postila.dblink_self = 'dbname=$PGDATABASE user=$PGUSER password=$PGPASSWORD'\" >> /etc/postgresql/10/main/postgresql.conf'"
    # sshdo "sudo sh -c 'echo \"port = 5432\" >> /etc/postgresql/10/main/postgresql.conf'"
    # sshdo "sudo sh -c 'echo \"\" > /etc/postgresql/10/main/pg_hba.conf'"
    # sshdo "sudo sh -c 'echo \"local all all trust\" >> /etc/postgresql/10/main/pg_hba.conf'"
    # sshdo "sudo sh -c 'echo \"host all all 127.0.0.1/32 trust\" >> /etc/postgresql/10/main/pg_hba.conf'"

sshdo "sudo /etc/init.d/postgresql restart"

    #sshdo "sudo -u postgres psql -c 'create database test;'"
    #sshdo "sudo -u postgres pgbench -i -F70 -s $s test"

    #sshdo "sudo -u postgres psql test -c 'create extension pg_prewarm;'"
    #sshdo "echo \"select format('select %L, pg_prewarm(%L);', relname, relname) from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public' where relkind in ('r', 'i')\gexec\" | sudo -u postgres psql test -qX"

    #echo "*** Only SELECTs, -T $duration -j1 -c24"
    #sshdo "sudo -u postgres pgbench -T $duration -j1 -c24 -M prepared -rS test"
    #echo "*** Mixed load, -T $duration -j1 -c24"
    #sshdo "sudo -u postgres pgbench -T $duration -j1 -c24 -M prepared -r test"
#echo "*** Mixed load, -s$s, -c$n, -n starting from $n, increment ny $increment"
#for iter in {1..8}
#do
#  sshdo "sudo -u postgres pgbench -s $s -j $n -c $n -M prepared test"
#  let "n+=$increment"
#done

    #echo "*** Only INSERTs, -T $duration -j1 -c24"
    #sshdo "sudo -u postgres pgbench -T $duration -j1 -c24 -M prepared -f /tmp/ins.bench -r test"
    #echo "*** Only UPDATEs, -T $duration -j1 -c24"
    #sshdo "sudo -u postgres pgbench -T $duration -j1 -c24 -M prepared -f /tmp/upd.bench -r test"

#echo
#echo "*** Only INSERTs, but this time with a primitive trigger"
#sshdo "sudo -u postgres psql test -c \"alter table pgbench_history add column iii int;\""
#sshdo "sudo -u postgres psql test -c \"create or replace function trig() returns trigger as 'begin return new; end;' language plpgsql;\""
#sshdo "sudo -u postgres psql test -c \"create trigger t_trig before insert or update on pgbench_history for each row execute procedure trig();\""
#sshdo "sudo -u postgres pgbench -T $duration -j1 -c24 -M prepared -f /tmp/ins.bench -r test"
#echo "*** Only UPDATEs, but this time with a primitive trigger"
#sshdo "sudo -u postgres pgbench -T $duration -j1 -c24 -M prepared -f /tmp/upd.bench -r test"

#echo "*** Only INSERTs, but this time with 2 (two) primitive triggers"
#sshdo "sudo -u postgres psql test -c \"create or replace function trig2() returns trigger as 'begin return new; end;' language plpgsql;\""
#sshdo "sudo -u postgres psql test -c \"create trigger t_trig2 before insert or update on pgbench_history for each row execute procedure trig2();\""
#sshdo "sudo -u postgres pgbench -T $duration -j1 -c24 -M prepared -f /tmp/ins.bench -r test"
#echo "*** Only UPDATEs, but this time with 2 (two) primitive trigger"
#sshdo "sudo -u postgres pgbench -T $duration -j1 -c24 -M prepared -f /tmp/upd.bench -r test"

    #sshdo "sudo -u postgres psql test -c 'select * from pg_stat_user_tables;'"
 
#    Prepare database
    sshdo "echo '================================================'"
    sshdo "echo 'Prepare database'"
    sshdo "s3cmd sync s3://p-dumps/dev.imgdata.ru/postila_ru.sql-20180503.bz2 ./"
    sshdo "s3cmd sync s3://p-dumps/dev.imgdata.ru/queries.sql ./"
    sshdo "bunzip2 ./postila_ru.sql-20180503.bz2"
    sshdo "sudo -u postgres psql -c 'create database postila_ru;'"
    sshdo "sudo -u postgres psql --set ON_ERROR_STOP=on postila_ru < postila_ru.sql-20180503"

    sshdo "echo '================================================'"
    sshdo "echo 'Execute queries'"
    sshdo "sudo -u postgres psql -d postila_ru -f ./queries.sql"
    #

#   Prepare and start pgBadger
    sshdo "echo '================================================'"
    sshdo "echo 'Prepare pgBadger'"
    version=postgresql-$pgVers-main
    date=$(date -d 'now' '+%Y%m%d')
    logdir=/var/log/postgresql

    sshdo "sudo -u postgres vacuumdb postila_ru -j 10 -v --analyze"
    
    sshdo "sudo apt-get -y install pgbadger"
    sshdo "sudo apt-get -y install libjson-xs-perl"
    sshdo "pgbadger -j 4 --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' ${logdir}/${version}.log -f stderr -o ~/${version}.json-${date}"
    sshdo "ls -al"
    
    sshdo "s3cmd put ${logdir}/${version}.log s3://p-dumps/dev.imgdata.ru/"
    sshdo "s3cmd put ~/${version}.json-${date} s3://p-dumps/dev.imgdata.ru/"

#   Prepare loganalyzer
    sshdo "echo '================================================'"
    sshdo "echo 'Prepare PHP'"
    sshdo "sudo apt-get -y install php5-cli"
    sshdo "sudo apt-get install php5-curl"
    #sshdo "sudo apt-get -y install git"
    sshdo "sudo apt-get install jq"
    sshdo "php --version"
    sshdo "s3cmd sync s3://p-dumps/tools/logloader.php ./"
    sshdo "s3cmd sync s3://p-dumps/tools/config.local.php ./"
    sshdo "cd ~/"
    sshdo "pwd"
    sshdo "ls -al"
    sshdo "php ./logloader.php --log=~/${version}.json-${date} --experiment=$EXPERIMENT_ID --expstep=$EXPERIMENT_STEP --token=$TOKEN"
    sshdo "ls -al"

echo "The end."
exit 0
