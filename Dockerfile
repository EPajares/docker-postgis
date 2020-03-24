FROM debian:buster-slim
LABEL  Maintainer="Tim Sutton <tim@kartoza.com>"

# TODO: Add option for ARGs
ENV PG_MAJOR=11
ENV POSTGIS_VERSION=3
ENV PLV8_VERSION=2.3.14
ENV PG_CONFIG="/usr/lib/postgresql/${PG_MAJOR}/bin/pg_config"

# Disable inadvert daemon starts and disable install recommends
RUN  dpkg-divert --local --rename --add /sbin/initctl \
   && echo 'apt::install-recommends "false";' >> /etc/apt/apt.conf.d/01-no-install-recommends

# Configure PostgreSQL repotirory
# TODO: check if `gdal-bin` is really necessary
RUN apt update && apt install -y build-essential gnupg2 wget ca-certificates rpl pwgen git \
   && echo "deb http://apt.postgresql.org/pub/repos/apt/ buster-pgdg main"  > /etc/apt/sources.list.d/postgresql.list \
   && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc -O- | apt-key add -

# Install Set versions
RUN apt update \
   && apt install -y "postgresql-client-${PG_MAJOR}" "postgresql-${PG_MAJOR}" "postgresql-server-dev-${PG_MAJOR}" \
   "postgresql-${PG_MAJOR}-postgis-${POSTGIS_VERSION}" "postgresql-${PG_MAJOR}-pgrouting" \
   "postgresql-${PG_MAJOR}-ogr-fdw" "postgresql-plpython3-${PG_MAJOR}" \
   osmosis osmctools osm2pgsql python3 python3-setuptools python3-pip  \
   && pip3 install  psycopg2-binary pyshp pyyaml osm_humanized_opening_hours


# Install specific version of osm2pgrouting
# TODO: Check if this can be installed via apt and do  set version as env var
RUN cd /tmp/ && wget http://security.ubuntu.com/ubuntu/pool/universe/b/boost1.62/libboost-program-options1.62.0_1.62.0+dfsg-5_amd64.deb \
   && dpkg -i libboost-program-options1.62.0_1.62.0+dfsg-5_amd64.deb \
   && wget http://ftp.br.debian.org/debian/pool/main/o/osm2pgrouting/osm2pgrouting_2.2.0-1_amd64.deb \
   && dpkg -i osm2pgrouting_2.2.0-1_amd64.deb \
   && rm -rf /tmp/*

# Install PLV8
RUN apt install -y python2 \
   && git config --global user.email "database@goat.io" \
   && git config --global user.name "Goat Project" \
   && cd /tmp/ &&  wget -q "https://github.com/plv8/plv8/archive/v${PLV8_VERSION}.tar.gz" \
   && tar -xvzf "v${PLV8_VERSION}.tar.gz" \
   && cd "plv8-${PLV8_VERSION}" \
   && GYP_CHROMIUM_NO_ACTION=0 make && make install \
   && apt purge -y python2 && rm -rf /tmp/*


# Run any additional tasks here that are too tedious to put in
# this dockerfile directly.
ADD env-data.sh /env-data.sh
ADD setup.sh /setup.sh
RUN chmod +x /setup.sh
RUN /setup.sh

ADD locale.gen /etc/locale.gen
RUN /usr/sbin/locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
RUN update-locale ${LANG}

# Copy customized pg_hba.conf.template
COPY pg_hba.conf.template /pg_hba.conf.template

# We will run any commands in this when the container starts
ADD docker-entrypoint.sh /docker-entrypoint.sh
ADD setup-conf.sh /
ADD setup-database.sh /
ADD setup-pg_hba.sh /
ADD setup-replication.sh /
ADD setup-ssl.sh /
ADD setup-user.sh /
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT /docker-entrypoint.sh
