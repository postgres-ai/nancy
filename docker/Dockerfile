FROM ubuntu:16.04

ARG PG_SERVER_VERSION

ENV PG_SERVER_VERSION=${PG_SERVER_VERSION:-11} \
    DEBIAN_FRONTEND=noninteractive

# add custom FTS dictionaries
ADD ./tsearch_data /usr/share/postgresql/$PG_SERVER_VERSION/tsearch_data

# logging ON; memory setting – for 2CPU/4096MB/SSD
ADD ./postgresql_${PG_SERVER_VERSION}_tweak.conf /postgresql.tweak.conf

# set up apt, add Postgres repo
RUN apt-get update
RUN apt-get install -y wget ca-certificates
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main $PG_SERVER_VERSION" > /etc/apt/sources.list.d/pgdg.list
RUN apt-get update
RUN apt-get install -y apt-utils

# install additional utilites
RUN apt-get install -y sudo git jq libjson-xs-perl vim
RUN apt-get install -y sysbench s3cmd sudo bzip2 python-software-properties software-properties-common
RUN apt-get install -y sysstat iotop moreutils psmisc

# install Postgres and postgres-specific packages
RUN apt-get install -y postgresql-$PG_SERVER_VERSION
RUN apt-get install -y postgresql-contrib-$PG_SERVER_VERSION
RUN apt-get install -y postgresql-plpython-$PG_SERVER_VERSION
RUN apt-get install -y postgresql-server-dev-$PG_SERVER_VERSION
RUN apt-get install -y postgresql-$PG_SERVER_VERSION-dbg
RUN apt-get install -y postgresql-$PG_SERVER_VERSION-pg-stat-kcache
RUN apt-get install -y postgresql-client-11

RUN apt-get install -y pgreplay
RUN apt-get install -y pspg
RUN git clone https://github.com/NikolayS/postgres_dba.git /root/postgres_dba
RUN apt-get install -y postgresql-$PG_SERVER_VERSION-repack
RUN git clone https://github.com/darold/pgbadger.git /root/pgbadger && cd /root/pgbadger && git checkout "tags/v10.3"

# install FlameGraph and generic perf
RUN git clone https://github.com/brendangregg/FlameGraph /root/FlameGraph
RUN apt-get install -y linux-tools-generic
# replace incorrect Debian perf wrapper with a symbolic link
RUN path=$(ls /usr/lib/linux-tools/*generic/perf | head -n 1) && ln -s -f "$path" /usr/bin/perf

# configure psql, configure Postgres
RUN echo "\\set dba '\\\\\\\\i /root/postgres_dba/start.psql'" >> ~/.psqlrc
RUN echo "\\setenv PAGER 'pspg -bX --no-mouse'" >> ~/.psqlrc
RUN echo "local   all all trust" > /etc/postgresql/$PG_SERVER_VERSION/main/pg_hba.conf
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/$PG_SERVER_VERSION/main/pg_hba.conf
RUN echo "listen_addresses='*'" >> /etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf
RUN echo "log_filename='postgresql-$PG_SERVER_VERSION-main.log'" >> /etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf

# prepare database 'test' with 'testuser'
RUN /etc/init.d/postgresql start && psql -U postgres -c "create database test" \
    && psql -U postgres -d test -c "CREATE EXTENSION pg_repack" \
    && psql -U postgres -c "CREATE ROLE testuser LOGIN password 'testuser' superuser" && /etc/init.d/postgresql stop

# apply 'tweaked' config
RUN cat /postgresql.tweak.conf >> /etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf

# prepare Postgres start script
RUN echo "#!/bin/bash" > /pg_start.sh && chmod a+x /pg_start.sh
RUN printf "sudo -u postgres /usr/lib/postgresql/$PG_SERVER_VERSION/bin/postgres -D /var/lib/postgresql/$PG_SERVER_VERSION/main -c config_file=/etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf \n" >> /pg_start.sh
# infinite sleep to allow restarting Postgres
RUN echo "/bin/bash -c \"trap : TERM INT; sleep infinity & wait\"" >> /pg_start.sh

# generate english locale for iostat + iostat-tool
RUN locale-gen en_US.UTF-8

# install pip and iostat-tool
RUN apt-get install curl
RUN curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
RUN python3 get-pip.py
RUN pip3 install iostat-tool

# install zfs utils
RUN apt-get install -y zfsutils-linux

# reduce images size
RUN rm -rf /tmp/*
RUN apt-get purge -y --auto-remove
RUN apt-get clean -y autoclean
RUN rm -rf /var/lib/apt/lists/*

EXPOSE 5432

#VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]

CMD ["/pg_start.sh"]
