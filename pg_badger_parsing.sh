#!/bin/bash
# written by Yorick
#
# Usage: pg_badger_parsing.sh                 - for parsing /var/log/postgresql/ after logrotate
#        pg_badger_parsing.sh postgresql.log  - specifying the file
#
# Requires: apt-get install libjson-xs-perl
#

hostname=$(hostname -f)
logfile=$NANCY_LOGFILE

[ "$logfile" = '' ] && logfile=$1

if [ ! -s ~/.s3cfg ]
then
  project=$NANCY_PROJECT
  [ "$(psql -X -A -t postgres_ai -c "select s3_access_key,s3_secret_key,s3_region from project where name='$project';" 2>/dev/null | wc -l)" -ne 1 ] && echo "FAIL: project=$project is invalid, exit" && exit 1
  s3cfg=$(psql -X -A -t postgres_ai -c "select s3_access_key,s3_secret_key,s3_region from project where name='$project';")
  (echo '[default]'
   echo "access_key = $(echo "$s3cfg" | awk -F '|' '{print $1}')"
   echo "secret_key = $(echo "$s3cfg" | awk -F '|' '{print $2}')"
   echo "region     = $(echo "$s3cfg" | awk -F '|' '{print $3}')"
  ) > ~/.s3cfg
fi

if [ "$logfile" != '' ]
then
  [ ! -s $logfile ] && echo "FAIL: file=$file is empty or absent, exit" && exit 1
  pgbadger -j 4 --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' "$logfile" -f stderr -o "$logfile.json" && gzip -vf "$logfile.json" && s3cmd put "$logfile.json.gz" s3://p-dumps/${hostname}-manual/
  echo "Listing (on S3 storage):"
  s3cmd ls s3://p-dumps/${hostname}-manual/
else
  version=postgresql-9.6-main
  date=$(date -d 'now' '+%Y%m%d')
  logdir=/var/log/postgresql
  pgbadger -j 4 --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' ${logdir}/${version}.log-${date}.gz -f stderr -o ${logdir}/${version}.json-${date} && gzip -vf ${logdir}/${version}.json-${date} && s3cmd put ${logdir}/${version}.*-${date}.gz s3://p-dumps/${hostname}/
  echo "Listing (on S3 storage):"
  s3cmd ls s3://p-dumps/$hostname/
fi
