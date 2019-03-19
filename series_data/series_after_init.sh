#!/bin/bash

readSql="
\set aid random(1, 100000 * :scale)
BEGIN;
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
END;
"
scanSql="
\set aid random(1, 100000 * :scale)
\SET limit random(1, 100)
BEGIN;
SELECT abalance FROM pgbench_accounts WHERE aid > :aid ORDER BY aid LIMIT :limit;
END;
"

writeSql="
\set aid random(1, 100000 * :scale)
\set bid random(1, 1 * :scale)
\set tid random(1, 10 * :scale)
\set delta random(-5000, 5000)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;
UPDATE pgbench_tellers SET tbalance = tbalance + :delta WHERE tid = :tid;
UPDATE pgbench_branches SET bbalance = bbalance + :delta WHERE bid = :bid;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);
END;
"

mkdir -p /storage/workload
echo "$readSql" > /storage/workload/read.sql
echo "$scanSql" > /storage/workload/scan.sql
echo "$writeSql" > /storage/workload/write.sql

#docker_exec su - postgres -c "psql -U postgres $DB_NAME -c \"create table pgbench_accounts_vac as select * from pgbench_accounts;\"" #### Will execute in after_db_restore.sql
#docker_exec bash -c "nohup psql -A -t -d bench -c \"vacuum analyze pgbench_accounts_vac\" &>/dev/null &" ####

echo "#!/bin/bash" > ~/bgvacuum.sh
echo "" >> ~/bgvacuum.sh
echo "while true; do" >> ~/bgvacuum.sh
echo "  psql -A -t -d bench -c \"vacuum analyze pgbench_accounts_vac\" &>/dev/null || sleep 1" >> ~/bgvacuum.sh
echo "done" >> ~/bgvacuum.sh
chmod 755 ~/bgvacuum.sh
bash -c "nohup ~/bgvacuum.sh &>/dev/null &" &