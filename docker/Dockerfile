FROM ubuntu:16.04

ARG PG_SERVER_VERSION

ENV PG_SERVER_VERSION=${PG_SERVER_VERSION:-10} \
    DEBIAN_FRONTEND=noninteractive

# add custom FTS dictionaries
ADD ./tsearch_data /usr/share/postgresql/$PG_SERVER_VERSION/tsearch_data
# logging ON; memory setting – for 2CPU/4096MB/SSD
ADD ./postgresql_${PG_SERVER_VERSION}_tweak.conf /postgresql.tweak.conf

RUN if [ "$PG_SERVER_VERSION" = "11" ]; then \
      export PG_CLIENT_VERSION=11; \
    else \
      export PG_CLIENT_VERSION=10; \
    fi

RUN if [ "$PG_SERVER_VERSION" = "11" ]; then \
      export PG_EXOTIC="postgresql-$PG_SERVER_VERSION-rum postgresql-$PG_SERVER_VERSION-powa"; \
    else \
      export PG_EXOTIC="postgresql-$PG_SERVER_VERSION-rum postgresql-$PG_SERVER_VERSION-powa postgresql-$PG_SERVER_VERSION-plsh"; \
    fi

# install Postgres and postgres-specific software:
#   - desired version of Postgres server,
#   - psql version 10+ (required by postgres_dba toolset)
#   - postgres_dba and pspg
#   - pgbadger 10+
#   - postgres_dba toolset
RUN apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8 \
      && echo "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main $PG_SERVER_VERSION" > /etc/apt/sources.list.d/pgdg.list \
      && apt-get update \
      && apt-get install -y sudo postgresql-$PG_SERVER_VERSION \
      && apt-get install -y postgresql-contrib-$PG_SERVER_VERSION postgresql-plpython-$PG_SERVER_VERSION postgresql-server-dev-$PG_SERVER_VERSION \
      && apt-get install -y "$PG_EXOTIC" \
      && apt-get install -y git postgresql-client-$PG_CLIENT_VERSION pspg pgreplay jq etcd libjson-xs-perl vim \
      && git clone https://github.com/NikolayS/postgres_dba.git /root/postgres_dba \
      && git clone https://github.com/darold/pgbadger.git /root/pgbadger && cd /root/pgbadger && git checkout "tags/v10.1"

# configure psql, configure postgres & check postgres start & stop & prepare start script
RUN echo "\\set dba '\\\\\\\\i /root/postgres_dba/start.psql'" >> ~/.psqlrc \
      && echo "\\setenv PAGER 'pspg -bX --no-mouse'" >> ~/.psqlrc \
      && echo "local   all all trust" > /etc/postgresql/$PG_SERVER_VERSION/main/pg_hba.conf \
      && echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/$PG_SERVER_VERSION/main/pg_hba.conf \
      && echo "listen_addresses='*'" >> /etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf \
      && echo "log_filename='postgresql-$PG_SERVER_VERSION-main.log'" >> /etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf \
      && /etc/init.d/postgresql start && psql -U postgres -c 'create database test;' && /etc/init.d/postgresql stop \
      && cat /postgresql.tweak.conf >> /etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf \
      && echo "#!/bin/bash" > /pg_start.sh && chmod a+x /pg_start.sh \
      && printf "sudo -u postgres /usr/lib/postgresql/$PG_SERVER_VERSION/bin/postgres -D /var/lib/postgresql/$PG_SERVER_VERSION/main -c config_file=/etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf & \n" >> /pg_start.sh \
      && echo "etcd" >> /pg_start.sh

EXPOSE 5432

#VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]

# etcd is not being actually used (it's for future needs), but it allows restart Postgres with container interruption
CMD ["/pg_start.sh"]
