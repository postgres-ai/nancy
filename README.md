[![CircleCI](https://circleci.com/gh/startupturbo/nancy.svg?style=svg)](https://circleci.com/gh/startupturbo/nancy)

Description
===
Nancy helps to conduct automated database experiments.

The Nancy Command Line Interface is a unified way to manage automated
database experiments either in clouds or on-premise.

Experiments are needed every time you:
 - add or remove indexes;
 - want to verify query optimization ideas;
 - need to tune database parameters;
 - want to perform performance/stress test for your DB;
 - are preparing to upgrade your DBMS to the new major version;
 - want to train ML model related to DB optimization.

Currently Nancy works only with PostgreSQL versions 9.6 and 10.

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

