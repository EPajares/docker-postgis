ARG PG_MAJOR=12

FROM postgres:${PG_MAJOR} AS pgroutingBuilder

ARG PG_MAJOR=12

ARG PGROUTING_VERSION=2.6.9
ENV PGROUTING_SHA256=86a3466030e153cd11a30d7c72e083da092e6f92a9af155d0a4e8801ca50f4c4

RUN set -ex \
 && apt update \
 && apt install -y \
        libboost-atomic1.67.0 \
        libboost-chrono1.67.0 \
        libboost-graph1.67.0 \
        libboost-date-time1.67.0 \
        libboost-program-options1.67.0 \
        libboost-system1.67.0 \
        libboost-thread1.67.0 \
        libcgal13 \
 && apt install -y \
        build-essential \
        cmake \
        wget \
        libboost-graph-dev \
        libcgal-dev \
        libpq-dev \
        postgresql-server-dev-${PG_MAJOR} \
 && wget -O pgrouting.tar.gz "https://github.com/goat-community/pgrouting/archive/v${PGROUTING_VERSION}.tar.gz" \
 && echo "$PGROUTING_SHA256 *pgrouting.tar.gz" | sha256sum -c - \
 && mkdir -p /usr/src/pgrouting \
 && tar \
        --extract \
        --file pgrouting.tar.gz \
        --directory /usr/src/pgrouting \
        --strip-components 1 \
 && rm pgrouting.tar.gz \
 && cd /usr/src/pgrouting \
 && mkdir build \
 && cd build \
 && cmake .. \
 && make \
 && make install

FROM postgres:${PG_MAJOR} AS plv8Builder

# Args need to be repeated for scope
ARG PLV8_VERSION=2.3.14
ARG PG_MAJOR=12

RUN echo 'apt::install-recommends "false";' >> /etc/apt/apt.conf.d/01-no-install-recommends \
   && apt update  && apt install -y build-essential \
    ca-certificates \
    wget \
    git-core \
    python \
    gpp \
    cpp \
    pkg-config \
    apt-transport-https \
    cmake \
    libc++-dev \
    libc++abi-dev \
    libtinfo5 \
    "postgresql-server-dev-${PG_MAJOR}" \
    "libc++1" \
  && mkdir -p /tmp/build \
  && cd /tmp/build \
  && wget -q "https://github.com/plv8/plv8/archive/v${PLV8_VERSION}.tar.gz" \
  && tar -xzf "v${PLV8_VERSION}.tar.gz" \
  && cd "/tmp/build/plv8-${PLV8_VERSION}" \
  && make static
RUN cd "/tmp/build/plv8-${PLV8_VERSION}" \
  && make install \
  && strip "/usr/lib/postgresql/${PG_MAJOR}/lib/plv8-${PLV8_VERSION}.so"


# Use a brand new images
FROM debian:buster-slim
LABEL  Maintainer="Alfredo Palhares <alfredo@palhares.me>"

# There need to be repeadted for scope
ARG PG_MAJOR=12
ARG PLV8_VERSION=2.3.14
ARG POSTGIS_VERSION=3

# Its important to have the Variables in runtime
ENV PG_CONFIG="/usr/lib/postgresql/${PG_MAJOR}/bin/pg_config"
ENV PG_VERSION=${PG_MAJOR}
ENV PGIS_VERSION=${POSTGIS_VERSION}

LABEL Version.PostgreSQL="${PG_VERSION}"
LABEL Version.PostGIS="${PGIS_VERSION}"
LABEL Version.PLV8="${PLV8_VERSION}"

# Disable inadvert daemon starts and disable install recommends
RUN  dpkg-divert --local --rename --add /sbin/initctl \
   && echo 'apt::install-recommends "false";' >> /etc/apt/apt.conf.d/01-no-install-recommends

# Configure PostgreSQL repotirory
# TODO: check if `gdal-bin` is really necessary
RUN apt update && apt install -y build-essential gnupg2 wget ca-certificates rpl pwgen git libc++1 libtinfo5 libc++abi1 \
   && echo "deb http://apt.postgresql.org/pub/repos/apt/ buster-pgdg main"  > /etc/apt/sources.list.d/postgresql.list \
   && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc -O- | apt-key add -

# Install Set versions
RUN apt update \
   && apt install -y "postgresql-client-${PG_MAJOR}" "postgresql-${PG_MAJOR}" "postgresql-server-dev-${PG_MAJOR}" \
   "postgresql-${PG_MAJOR}-postgis-${PGIS_VERSION}" \
   "postgresql-${PG_MAJOR}-ogr-fdw" "postgresql-plpython3-${PG_MAJOR}" "postgis" \
   osmosis osmctools osm2pgsql python3 python3-setuptools python3-pip  \
   && pip3 install  psycopg2-binary pyshp pyyaml osm_humanized_opening_hours boto3


# Install specific version of osm2pgrouting
# TODO: Check if this can be installed via apt and do  set version as env var
RUN cd /tmp/ && wget http://security.ubuntu.com/ubuntu/pool/universe/b/boost1.62/libboost-program-options1.62.0_1.62.0+dfsg-5_amd64.deb \
   && dpkg -i libboost-program-options1.62.0_1.62.0+dfsg-5_amd64.deb \
   && wget http://ftp.br.debian.org/debian/pool/main/o/osm2pgrouting/osm2pgrouting_2.2.0-1_amd64.deb \
   && dpkg -i osm2pgrouting_2.2.0-1_amd64.deb \
   && rm -rf /tmp/*

# There is the wrong version of postgis being installed as dependency
# Currently best way is to purge afterwards
RUN wrongDep=$(dpkg -l | grep  postgresql-${PG_VERSION}-postgis- | grep --invert-match  postgresql-${PG_VERSION}-postgis-${PGIS_VERSION}   | cut -d ' ' -f 3) \
   && apt purge -y $wrongDep

# COPY PLV8
COPY --from=plv8Builder /usr/lib/postgresql/${PG_MAJOR}/lib/plv8-${PLV8_VERSION}.so /usr/lib/postgresql/${PG_MAJOR}/lib/plv8-${PLV8_VERSION}.so
COPY --from=plv8Builder /usr/lib/postgresql/${PG_MAJOR}/lib/bitcode /usr/lib/postgresql/${PG_MAJOR}/lib/bitcode
COPY --from=plv8Builder /usr/share/postgresql/${PG_MAJOR}/extension /usr/share/postgresql/${PG_MAJOR}/extension

# Copy PGrouting
# The .so file generated only contains major or minor therefore a variable PGROUTING_MAJOR is defined
ARG PGROUTING_MAJOR=2.6
COPY --from=pgroutingBuilder /usr/lib/postgresql/${PG_MAJOR}/lib/libpgrouting-${PGROUTING_MAJOR}.so \
   /usr/lib/postgresql/${PG_MAJOR}/lib/libpgrouting-${PGROUTING_MAJOR}.so
COPY --from=pgroutingBuilder /usr/share/postgresql/${PG_MAJOR}/extension\
   /usr/share/postgresql/${PG_MAJOR}/extension


# Run any additional tasks here that are too tedious to put in
# this dockerfile directly.
COPY env-data.sh /env-data.sh
COPY setup.sh /setup.sh
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
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY setup-conf.sh /
COPY setup-database.sh /
COPY setup-pg_hba.sh /
COPY setup-replication.sh /
COPY setup-ssl.sh /
COPY setup-user.sh /
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT /docker-entrypoint.sh
