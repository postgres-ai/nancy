#!/bin/bash
basedir=/var/lib/postgresql
[ "$1" != '' ] && basedir=$1
incoming_dir=$basedir/$(basename $0).in
outcoming_dir=$basedir/$(basename $0).out
dbname=pgreplay_tmp
target_dbname='postila_ru'

pidfile=/var/tmp/`basename $0`.pid
if [ -s ${pidfile} ] && kill -0 `cat ${pidfile}` 2>/dev/null; then exit; fi
echo $$ > ${pidfile}

[ ! -d $incoming_dir ]  && mkdir $incoming_dir
[ ! -d $outcoming_dir ] && mkdir $outcoming_dir

function drop_sessions2db {
  psql -q -A -t $dbname -c 'set statement_timeout = 0' -c "SELECT pg_terminate_backend(pg_stat_activity.pid)
    FROM pg_stat_activity
    WHERE pg_stat_activity.datname = '"$dbname"'
      AND pid <> pg_backend_pid();"
}

function recreate_db {
  echo "Recreating DB for convertize..."
  echo "Dropping  DB \"$dbname\" sessions if exist"
  drop_sessions2db
  echo "Dropping  DB \"$dbname\""
  dropdb $dbname
  echo "Creating DB \"$dbname\""
  createdb $dbname
  echo "Creating table \"postgres_log\""
  psql -q -A -t $dbname -c 'set statement_timeout = 0' -c 'CREATE TABLE postgres_log
  (
    log_time timestamp(3) with time zone,
    user_name text,
    database_name text,
    process_id integer,
    connection_from text,
    session_id text,
    session_line_num bigint,
    command_tag text,
    session_start_time timestamp with time zone,
    virtual_transaction_id text,
    transaction_id bigint,
    error_severity text,
    sql_state_code text,
    message text,
    detail text,
    hint text,
    internal_query text,
    internal_query_pos integer,
    context text,
    query text,
    query_pos integer,
    location text,
    application_name text,
    PRIMARY KEY (session_id, session_line_num)
  );'
  echo '=============='
}

function normalize_db {
  echo 'Data normalizing...'
  echo -ne "We have records:\t"
  psql $dbname -A -t -q -c "SELECT count(1) FROM postgres_log;"
  echo "Cleaning..."
  psql $dbname -A -t -q -c 'set statement_timeout = 0' -c "DELETE from postgres_log where database_name<>'"$target_dbname"';"
  psql $dbname -A -t -q -c 'set statement_timeout = 0' -c "DELETE from postgres_log where database_name is null;"
  echo -ne "After:\t"
  psql $dbname -A -t -q -c "SELECT count(1) FROM postgres_log;"
  echo "Obfuscation of $dbname"
  psql $dbname -A -t -q -c 'set statement_timeout = 0' -c "UPDATE postgres_log set database_name='test';"
  psql $dbname -A -t -q -c 'set statement_timeout = 0' -c "UPDATE postgres_log set user_name='testuser';"
  echo '=============='
}

for logfile in $(find $incoming_dir/ -type f -iname '*_postgresql-9.6-*' -a ! -iname '*.processed' )
do
  recreate_db

  if [[ $(echo "$logfile" | grep -ci '.gz$') -eq 1 ]]
  then
    echo "Ungziping data..."
    gzip -df $logfile
    logfile="${logfile%'.gz'}"
  fi

  echo "Check & repair UTF8..."
  iconv -f utf-8 -t utf-8 -c $logfile > $logfile.tmp && mv $logfile.tmp $logfile
  echo "Loading $logfile to $dbname"
  psql $dbname -A -t -q -c 'set statement_timeout = 0' -c "COPY postgres_log FROM '"$logfile"' WITH csv;" && mv $logfile $logfile.processed

  normalize_db

  echo "Patching data..."
  psql $dbname -A -t -q -c 'set statement_timeout = 0' -c "set statement_timeout = 0;" -c "UPDATE postgres_log SET
  log_time = log_time - CAST(substring(message FROM E'\\\\d+.\\\\d* ms') AS interval),
    message = regexp_replace(message, E'^duration: \\\\d+.\\\\d* ms  ', '')
    WHERE error_severity = 'LOG' AND message ~ E'^duration: \\\\d+.\\\\d* ms  ';"

  echo "Unloading data to $outcoming_dir/$(basename $logfile).updated"
  psql $dbname -A -t -q -c 'set statement_timeout = 0' -c "\copy (SELECT
          to_char(log_time, 'YYYY-MM-DD HH24:MI:SS.MS TZ'),
                  user_name, database_name, process_id, connection_from,
                  session_id, session_line_num, command_tag, session_start_time,
                  virtual_transaction_id, transaction_id, error_severity,
                  sql_state_code, message, detail, hint, internal_query,
                  internal_query_pos, context, query, query_pos, location, application_name
             FROM postgres_log ORDER BY log_time, session_line_num)
             TO '"$outcoming_dir/$(basename $logfile).updated"' WITH CSV;"

  echo "Creating $(basename $logfile).pgreplay and $(basename $logfile).stats"
  pgreplay -f -c -o $outcoming_dir/$(basename $logfile).pgreplay $outcoming_dir/$(basename $logfile).updated > $outcoming_dir/$(basename $logfile).stats 2>&1
  #pgreplay -r -j $outcoming_dir/$(basename $logfile).pgreplay
  echo "Done!"
  echo
done

rm -f ${pidfile}
