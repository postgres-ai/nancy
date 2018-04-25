#!/bin/bash
# written by Yorick
#
# Usage: pg_badger_parsing.sh                 - for parsing /var/log/postgresql/ after logrotate
#        pg_badger_parsing.sh postgresql.log  - specifying the file
#
# Requires: apt-get install libjson-xs-perl
#

hostname=$(hostname -f)

if [ ! -s ~/.s3cfg ]
then
  s3cfg=$(psql -A -t postgres_ai -c 'select s3_access_key,s3_secret_key,s3_region from project;' | grep -v ^Tim)
  (echo '[default]'
   echo "access_key = $(echo "$s3cfg" | awk -F '|' '{print $1}')"
   echo "secret_key = $(echo "$s3cfg" | awk -F '|' '{print $2}')"
   echo "region     = $(echo "$s3cfg" | awk -F '|' '{print $3}')"
  ) > ~/.s3cfg
fi

if [ "$1" != '' ]
then
  pgbadger -j 4 --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' "$1" -f stderr -o "$1.json" && gzip -vf "$1.json" && s3cmd put "$1.json.gz" s3://p-dumps/${hostname}-manual/
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
