FROM ubuntu:16.04

LABEL maintainer="ru@postgresql.org"

ARG PG_VERSION
ARG AWS_EC2_TYPE

ENV PG_VERSION=$PG_VERSION \
    AWS_EC2_TYPE=$AWS_EC2_TYPE \
    DEBIAN_FRONTEND=noninteractive

ADD ./ec2_postgres_configs/$PG_VERSION /pg_configs
ADD ./tmp/tsearch_data /usr/share/postgresql/$PG_VERSION/tsearch_data

# install software
RUN apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8 \
      && echo "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main"> /etc/apt/sources.list.d/pgdg.list \
      && apt-get update && apt-get install -y postgresql-$PG_VERSION postgresql-contrib-$PG_VERSION postgresql-plpython-$PG_VERSION \
      && apt-get install -y postgresql-$PG_VERSION-plsh postgresql-server-dev-$PG_VERSION postgresql-$PG_VERSION-rum \
      && apt-get install -y git postgresql-client-10 pspg pgreplay pgbadger libjson-xs-perl \
      && apt-get install -y s3cmd sudo bzip2 python-software-properties software-properties-common php7.0-curl \
      && git clone https://github.com/NikolayS/postgres_dba.git /root/postgres_dba

# configure psql, configure postgres & check postgres start & stop & prepare start script
RUN echo "\\set dba '\\\\\\\\i /root/postgres_dba/start.psql'" >> ~/.psqlrc \
      && echo "\\setenv PAGER 'pspg -bX --no-mouse'" >> ~/.psqlrc \
      && echo "local   all all trust" > /etc/postgresql/$PG_VERSION/main/pg_hba.conf \
      && echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/$PG_VERSION/main/pg_hba.conf \
      && echo "listen_addresses='*'" >> /etc/postgresql/$PG_VERSION/main/postgresql.conf \
      && cat /pg_configs/$AWS_EC2_TYPE >> /etc/postgresql/$PG_VERSION/main/postgresql.conf \
      && /etc/init.d/postgresql start && psql -U postgres -c 'create database test;' && /etc/init.d/postgresql stop \
      && echo "#!/bin/bash" > /pg_start.sh && chmod a+x /pg_start.sh \
      && echo "sudo -u postgres /usr/lib/postgresql/$PG_VERSION/bin/postgres -D /var/lib/postgresql/$PG_VERSION/main -c config_file=/etc/postgresql/$PG_VERSION/main/postgresql.conf" >> /pg_start.sh

EXPOSE 5432

VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]

CMD ["/pg_start.sh"]
#CMD ["sudo", "-u", "postgres", "/usr/lib/postgresql/$PG_VERSION/bin/postgres", "-D", "/var/lib/postgresql/$PG_VERSION/main", "-c", "config_file=/etc/postgresql/$PG_VERSION/main/postgresql.conf"]

