[![CircleCI](https://circleci.com/gh/startupturbo/nancy.svg?style=svg)](https://circleci.com/gh/startupturbo/nancy)

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
* Supported locations for experimental runs:
  * Any machine with Docker installed
  * AWS EC2:
    * Run on AWS EC2 Spot Instances (using Docker Machine)
    * Allow to specify EC2 instance type
    * Auto-detect and use current lowest EC2 Spot Instance prices
* Support local or remote (S3) files – config, dump, etc
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
To use Nancy CLI you need Linux or MacOS with installed Docker. If you plan
to run experiments in AWS EC2 instances, you also need Docker Machine
(https://docs.docker.com/machine/).

Installation
===
```bash
git clone https://github.com/startupturbo/nancy
echo "export PATH=\$PATH:"$(pwd)"/nancy" >> ~/.bashrc
source ~/.bashrc
```

Getting started
===
Start with these commands:
```bash
nancy help
nancy run help
```

