FROM ubuntu:16.04

ENV PG_SERVER_VERSION=10

RUN apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8 \
      && echo "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main"> /etc/apt/sources.list.d/pgdg.list \
      && apt-get update && apt-get install -y sudo postgresql-$PG_SERVER_VERSION \
      && apt-get install -y postgresql-contrib-$PG_SERVER_VERSION postgresql-plpython-$PG_SERVER_VERSION \
      && apt-get install -y pspg git jq vim \
      && git clone https://github.com/NikolayS/postgres_dba.git /root/postgres_dba

# configure psql, configure postgres & check postgres start & stop & prepare start script
RUN echo "\\set dba '\\\\\\\\i /root/postgres_dba/start.psql'" >> ~/.psqlrc \
      && echo "\\setenv PAGER 'pspg -bX --no-mouse'" >> ~/.psqlrc \
      && echo "local   all all trust" > /etc/postgresql/$PG_SERVER_VERSION/main/pg_hba.conf \
      && echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/$PG_SERVER_VERSION/main/pg_hba.conf \
      && echo "listen_addresses='*'" >> /etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf \
      && echo "log_filename='postgresql-$PG_SERVER_VERSION-main.log'" >> /etc/postgresql/$PG_SERVER_VERSION/main/postgresql.conf \
      && /etc/init.d/postgresql start \
      && psql -U postgres -c 'create database test;' \
      && psql -U postgres test -c 'create table t1 as select i from generate_series(1, 100000) _(i);' \
      && /etc/init.d/postgresql stop

EXPOSE 5432

