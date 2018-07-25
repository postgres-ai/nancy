[![CircleCI](https://circleci.com/gh/postgres-ai/nancy.svg?style=svg)](https://circleci.com/gh/postgres-ai/nancy)

Description
===
Nancy helps to conduct automated database experiments.

The Nancy Command Line Interface is a unified way to manage automated
database experiments either in clouds or on-premise.

What is a Database Experiment?
===
Database experiment is a set of actions performed to test
 * (a) specified SQL queries ("workload")
 * (b) on specified machine / OS / Postgres version ("environment")
 * (c) against specified database ("object")
 * (d) with an optional change – some DDL or config change ("target" or "delta").

Two main goals for any database experiment:
 * (1) validation – check that the specified workload is valid,
 * (2) benchmark – perform deep SQL query analysis.

Database experiments are needed when you:
 - add or remove indexes;
 - for a new DB schema change, want to validate it and estimate migration time;
 - want to verify some query optimization ideas;
 - tune database configuration parameters;
 - do capacity planning and want to stress-test your DB in some environment;
 - plan to upgrade your DBMS to a new major version;
 - want to train ML model related to DB optimization.

Currently Supported Features
===
* Experiments are conducted in a Docker container with extended Postgres setup
* Supported Postgres versions: 9.6, 10
* Postgres config specified via options, may be partial
* Supported locations for experimental runs:
  * Any machine with Docker installed
  * AWS EC2:
    * Run on AWS EC2 Spot Instances (using Docker Machine)
    * Allow to specify EC2 instance type
    * Auto-detect and use current lowest EC2 Spot Instance prices
    * Support i3 instances (with NVMe SSD drives)
    * Support arbitrary-size EBS volumes
* Support local or remote (S3) files – config, dump, etc
* The object (database) can be specified in various ways:
  * Plain text
  * Dump file (.sql, .gz, .bz2) – :warning: only plain, single-file dumps are currently supported
* What to test (a.k.a. "target" or "delta"):
  * Test Postgres parameters change
  * Test DDL change (specified as "do" and "undo" SQL to return state)
* Supported types of workload:
  * Use custom SQL as workload
  * Use "real workload" prepared using Postgres logs
* For "real workload", allow replaying it with increased speed
* Allow to keep container alive for specified time after all steps are done
* Collected artifacts:
  * Workload SQL logs
  * Deep SQL query analysis report

Requirements
===
1) To use Nancy CLI you need Linux or MacOS with installed Docker.

2) To run on AWS EC2 instances, you also need:
  * AWS CLI https://aws.amazon.com/en/cli/
  * Docker Machine https://docs.docker.com/machine/
  * jq https://stedolan.github.io/jq/


Installation
===

In the minimal configuration, only two steps are needed:

1) Install Docker (for Ubuntu/Debian: `sudo apt-get install docker`)

2) Clone this repo and adjust `$PATH`:
```bash
git clone https://github.com/startupturbo/nancy
echo "export PATH=\$PATH:"$(pwd)"/nancy" >> ~/.bashrc
source ~/.bashrc
```

Additionally, to allow use of AWS EC2 instances:

3) Follow instructions https://docs.aws.amazon.com/cli/latest/userguide/installing.html

4) Follow instructions https://docs.docker.com/machine/install-machine/

5) install jq (for Ubuntu/Debian: `sudo apt-get install jq`)

Getting started
===
Start with these commands:
```bash
nancy help
nancy run help
```

"Hello World!"
===
Locally:
```bash
echo "create table hello_world as select i::int4 from generate_series(1, (10^6)::int) _(i);" > ./sample.dump

# "Clean run": w/o index
# (seqscan is expected, total time ~150ms, depending on resources)
nancy run \
  --run-on localhost \
  --db-dump file://$(pwd)/sample.dump.bz2 \
  --tmp-path /tmp \
  --workload-custom-sql "select count(1) from hello_world where i between 100000 and 100010;"

# Now check how a regular btree index affects performance
# (expected total time: ~0.05ms)
nancy run \
  --run-on localhost \
  --db-dump file://$(pwd)/sample.dump.bz2 \
  --tmp-path /tmp \
  --workload-custom-sql "select count(1) from hello_world where i between 100000 and 100010;" \
  --target-ddl-do "create index i_hello_world_i on hello_world(i);" \
  --target-ddl-undo "drop index i_hello_world_i;"
```

On AWS EC2:
```bash
nancy run \
  --run-on aws \
  --aws-ec2-type "i3.large" \
  --aws-keypair-name awskey --aws-ssh-key-path file://$(echo ~)/.ssh/awskey.pem  \
  --db-dump "create table a as select i::int4 from generate_series(1, (10^9)::int) _(i);" \
  --workload-custom-sql "select count(1) from a where i between 10 and 20;"
```

