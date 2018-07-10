FROM ubuntu:16.04

ARG PG_SERVER_VERSION

ENV PG_SERVER_VERSION=${PG_SERVER_VERSION:-10} \
    DEBIAN_FRONTEND=noninteractive

# add custom FTS dictionaries
ADD ./tsearch_data /usr/share/postgresql/$PG_SERVER_VERSION/tsearch_data
# logging ON; memory setting – for 2CPU/4096MB/SSD
ADD ./postgresql_${PG_SERVER_VERSION}_tweak.conf /postgresql.tweak.conf

# install Postgres and postgres-specific software:
#   - desired version of Postgres server,
#   - psql version 10
#   - postgres_dba and pspg
#   - pgbadger (modified, not lowercasing DB object names, auto_explain compatibility)
RUN apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8 \
      && echo "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main"> /etc/apt/sources.list.d/pgdg.list \
      && apt-get update && apt-get install -y sudo postgresql-$PG_SERVER_VERSION \
      && apt-get install -y postgresql-contrib-$PG_SERVER_VERSION postgresql-plpython-$PG_SERVER_VERSION \
      && apt-get install -y postgresql-$PG_SERVER_VERSION-plsh postgresql-server-dev-$PG_SERVER_VERSION \
      && apt-get install -y postgresql-$PG_SERVER_VERSION-rum \
      && apt-get install -y git postgresql-client-10 pspg pgreplay jq etcd libjson-xs-perl \
      && perl -MCPAN -e'install Text::CSV_XS' \
      && git clone https://github.com/NikolayS/postgres_dba.git /root/postgres_dba \
      && git clone https://github.com/NikolayS/pgbadger.git /root/pgbadger

# additionally, install newer NodeJS, npm, Sqitch, and more
RUN wget -q -S -O - https://deb.nodesource.com/setup_8.x | sudo bash \
      && apt-get install -y s3cmd sudo bzip2 python-software-properties software-properties-common \
      && apt-get install -y build-essential cpanminus libdbd-pg-perl nginx netcat npm \
      && npm install -g newman ava \
      && sudo cpanm --quiet --notest App::Sqitch

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
