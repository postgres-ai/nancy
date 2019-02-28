FROM ubuntu:16.04

ARG PG_SERVER_VERSION

ENV PG_SERVER_VERSION=${PG_SERVER_VERSION:-11} \
    DEBIAN_FRONTEND=noninteractive

# add custom FTS dictionaries
ADD ./tsearch_data /usr/share/postgresql/$PG_SERVER_VERSION/tsearch_data

# logging ON; memory setting – for 2CPU/4096MB/SSD
ADD ./postgresql_${PG_SERVER_VERSION}_tweak.conf /postgresql.tweak.conf

RUN if [ "$PG_SERVER_VERSION" = "11" ]; then \
      export PG_EXTRA="postgresql-$PG_SERVER_VERSION-rum"; \
    else \
      export PG_EXTRA="postgresql-$PG_SERVER_VERSION-rum postgresql-$PG_SERVER_VERSION-plsh"; \
    fi

# install Postgres and postgres-specific software:
#   - desired version of Postgres server,
#   - psql version 10+ (required by postgres_dba toolset)
#   - postgres_dba and pspg
#   - pgbadger 10+
#   - postgres_dba toolset
#   - pg_repack

RUN apt-get update
RUN apt-get install -y wget ca-certificates
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main $PG_SERVER_VERSION" > /etc/apt/sources.list.d/pgdg.list
RUN apt-get update
RUN apt-get install -y apt-utils
RUN apt-get install -y postgresql-$PG_SERVER_VERSION
RUN apt-get install -y postgresql-contrib-$PG_SERVER_VERSION
RUN apt-get install -y postgresql-plpython-$PG_SERVER_VERSION
RUN apt-get install -y postgresql-server-dev-$PG_SERVER_VERSION
RUN apt-get install -y postgresql-$PG_SERVER_VERSION-pg-stat-kcache
RUN apt-get install -y "$PG_EXTRA"
RUN apt-get install -y postgresql-client-11
RUN apt-get install -y sudo git pspg pgreplay jq libjson-xs-perl vim
RUN git clone https://github.com/NikolayS/postgres_dba.git /root/postgres_dba
RUN git clone https://github.com/darold/pgbadger.git /root/pgbadger && cd /root/pgbadger && git checkout "tags/v10.1"
RUN apt-get install -y postgresql-$PG_SERVER_VERSION-repack
RUN apt-get install -y sysbench s3cmd sudo bzip2 python-software-properties software-properties-common

# add perf and FlameGraph support for AWS
RUN apt-get install -y linux-tools-aws
RUN apt-get install -y perf-tools-unstable
RUN git clone https://github.com/brendangregg/FlameGraph /root/FlameGraph

# configure psql, configure postgres & check postgres start & stop & prepare start script
RUN echo "\\set dba '\\\\\\\\i /root/postgres_dba/start.psql'" >> ~/.psqlrc
RUN echo "\\setenv PAGER 'pspg -bX --no-mouse'" >> ~/.psqlrc
RUN echo "local   all all trust" > /etc/postgresql/$PG_SERVER_VERSION/main/pg_hba.conf
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/$PG_SERVER_VERSION/main/pg_hba.conf
RUN echo "listen_addresses='*'" >> /etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf
RUN echo "log_filename='postgresql-$PG_SERVER_VERSION-main.log'" >> /etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf

RUN /etc/init.d/postgresql start && psql -U postgres -c 'create database test;' \
    && psql -U postgres -d test -c "CREATE EXTENSION pg_repack" \
    && psql -U postgres -c "CREATE ROLE testuser LOGIN password 'testuser' superuser" && /etc/init.d/postgresql stop

RUN cat /postgresql.tweak.conf >> /etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf
RUN echo "#!/bin/bash" > /pg_start.sh && chmod a+x /pg_start.sh
RUN printf "sudo -u postgres /usr/lib/postgresql/$PG_SERVER_VERSION/bin/postgres -D /var/lib/postgresql/$PG_SERVER_VERSION/main -c config_file=/etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf \n" >> /pg_start.sh

# ininity sleep to allow restarting Postgres
RUN echo "/bin/bash -c \"trap : TERM INT; sleep infinity & wait\"" >> /pg_start.sh

# reduce images size
RUN rm -rf /tmp/*
RUN apt-get purge -y --auto-remove
RUN apt-get clean -y autoclean
RUN rm -rf /var/lib/apt/lists/*

EXPOSE 5432

#VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]

CMD ["/pg_start.sh"]
