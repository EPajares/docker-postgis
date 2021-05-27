ARG PG_MAJOR=12

FROM postgres:${PG_MAJOR} AS pgroutingBuilder

ARG PG_MAJOR=12

ARG PGROUTING_VERSION=2.6.11
ENV PGROUTING_SHA256=01f8a55d944a7ee2ea6a769a7a76614feac98fa375733e3fe345fa4342a79969

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



FROM crunchydata/crunchy-postgres-gis:centos7-12.5-3.0-4.4.2 AS boost-builder
USER root
RUN yum-config-manager --save --setopt=crunchypg12.skip_if_unavailable=true \
    && yum install -y epel-release \
    && yum update -y

RUN yum install -y \
    git \
    gcc \
    gcc-c++ \
    clang \
	llvm5.0 \
	centos-release-scl-rh \
	llvm-toolset-7-llvm \
	devtoolset-7 \
	libcxx \
	libcxx-devel \
	python2 \
	python3 \
	wget \
    bzip2
RUN yum install -y llvm-toolset-7-clang
RUN wget https://boostorg.jfrog.io/artifactory/main/release/1.67.0/source/boost_1_67_0.tar.bz2 \
	&& tar --bzip2 -xf boost_1_67_0.tar.bz2 \
	&& cd  boost_1_67_0 &&  ./bootstrap.sh --with-libraries=atomic,chrono,graph,date_time,program_options,system,thread \
	&& ./b2 install



FROM crunchydata/crunchy-postgres-gis:centos7-12.5-3.0-4.4.2 AS plv8

USER root
ARG PLV8_VERSION=2.3.14

RUN yum-config-manager --save --setopt=crunchypg12.skip_if_unavailable=true \
   && yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm \
   && yum install -y epel-release \
   && yum update -y

RUN yum install -y \
    git \
    gcc \
    gcc-c++ \
    clang \
    llvm5.0 \
    centos-release-scl-rh \
    llvm-toolset-7-llvm \
    devtoolset-7 \
    llvm-toolset-7-clang \
    libcxx \
    libcxx-devel \
    python2 \
    python3 \
    wget \
    bzip2 \
    mpfr-devel \
    gmp-devel mpfr

RUN yum install -y llvm-toolset-7-llvm llvm-toolset-7-clang

RUN yum install -y postgresql12-devel postgresql-contrib postgresql-devel
RUN wget https://ftp.gnu.org/gnu/glibc/glibc-2.18.tar.gz \
	&& tar -zxvf glibc-2.18.tar.gz \
	&& cd glibc-2.18 && mkdir build \
	&& cd build \
	&& ../configure --prefix=/usr --disable-profile --enable-add-ons --with-headers=/usr/include --with-binutils=/usr/bin \
    && cd /glibc-2.18/build && make && make install

RUN wget https://github.com/plv8/plv8/archive/v2.3.14.tar.gz \
	&& tar -xvzf v2.3.14.tar.gz \
    && cp -rf /usr/lib64/pgsql/pgxs /usr/pgsql-12/lib/ \
    && cd /plv8-2.3.14 &&  make PG_CONFIG=/usr/pgsql-12/bin/pg_config \
    && cd /plv8-2.3.14 && make PG_CONFIG=/usr/pgsql-12/bin/pg_config install

FROM crunchydata/crunchy-postgres-gis-ha:centos7-12.5-3.0-4.4.2 as libsBuilder
ARG PG_MAJOR=12
ARG PGROUTING_MAJOR=2.6
USER 0
RUN yum-config-manager --save --setopt=crunchypg12.skip_if_unavailable=true \
    && yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm \
    && yum install -y epel-release \
    && yum update -y

RUN yum install -y llvm-toolset-7-clang \
    git \
    gcc \
    gcc-c++ \
    clang \
	llvm5.0 \
	centos-release-scl-rh \
	llvm-toolset-7-llvm \
	devtoolset-7 \
	llvm-toolset-7-clang \
	libcxx \
	libcxx-devel \
	python2 \
	python3 \
	wget \
    bzip2 \
    mpfr-devel \
    gmp-devel mpfr \
    boost-devel

RUN wget https://cmake.org/files/v3.2/cmake-3.2.0.tar.gz \
	&&   tar -zxvf cmake-3.2.0.tar.gz \
	&& cd  cmake-3.2.0 \
	&& ./bootstrap \
	&& gmake \
	&& gmake install


RUN wget https://github.com/CGAL/cgal/archive/refs/tags/releases/CGAL-4.13.2.tar.gz \
	&& tar -zxvf CGAL-4.13.2.tar.gz \
	&& cd cgal-releases-CGAL-4.13.2 \
	&& mkdir build \
	&& cd build \
	&& cmake .. \
	&& make \
	&& make install

RUN wget https://ftp.gnu.org/gnu/gcc/gcc-5.2.0/gcc-5.2.0.tar.gz \
	&& tar -xvf gcc-5.2.0.tar.gz \
	&& cd gcc-5.2.0 \
	&& ./contrib/download_prerequisites \
	&& mkdir gcc-temp \
	&& cd gcc-temp \
	&& ../configure --enable-checking=release --enable-languages=c,c++ --disable-multilib \
	&& make -j8

FROM crunchydata/crunchy-postgres-gis-ha:centos7-12.5-3.0-4.5.1
ARG PG_MAJOR=12
ARG PGROUTING_MAJOR=2.6
USER 0
RUN yum-config-manager --save --setopt=crunchypg12.skip_if_unavailable=true \
    && yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm \
    && yum install -y epel-release \
    && yum update -y

RUN yum install -y llvm-toolset-7-clang \
    git \
    gcc \
    gcc-c++ \
    clang \
	llvm5.0 \
	centos-release-scl-rh \
	llvm-toolset-7-llvm \
	devtoolset-7 \
	llvm-toolset-7-clang \
	libcxx \
	libcxx-devel \
	python2 \
	python3 \
	wget \
    bzip2 \
    mpfr-devel \
    gmp-devel mpfr \
    boost-devel \
    cmake \
    expat \
    expat-devel \
    ogr_fdw12 \
    postgresql12-plpython3 \
    autoconf \
    automake \
    zlib-devel \
    osm2pgsql \
    spatialindex-devel

RUN yum install -y llvm-toolset-7-clang postgresql12-devel postgresql-devel


#Looks like that centos doesnt have packages for yum manager, so it should be installed as prebuilt binary
RUN wget https://github.com/openstreetmap/osmosis/releases/download/0.48.3/osmosis-0.48.3.tgz \
    && mkdir osmosis \
    && mv osmosis-0.48.3.tgz osmosis \
    && cd osmosis \
    && tar xvfz osmosis-0.48.3.tgz \
    && rm osmosis-0.48.3.tgz \
    && chmod a+x bin/osmosis \
    && mv bin/osmosis /usr/bin/

RUN git clone https://github.com/ramunasd/osmctools.git \
  && cd osmctools \
  && autoreconf --install \
  && ./configure \
  && make install

COPY requirements.txt /tmp/
RUN pip3 install --upgrade pip setuptools \
   && pip3 install --user --no-cache-dir --no-warn-script-location -r /tmp/requirements.txt

RUN wget https://github.com/pgRouting/osm2pgrouting/archive/refs/tags/v2.2.0.zip \
    && unzip v2.2.0.zip \
    && cd osm2pgrouting-2.2.0 \
    && cmake -H. -Bbuild \
    && cd build \
    && make \
    && make install

RUN cd /tmp/ && wget https://github.com/pramsey/pgsql-arraymath/archive/master.zip && unzip master.zip && rm -rf master.zip && cd pgsql-arraymath-master && make && make install

#Install floatvec extension
RUN cd /tmp/ && wget https://github.com/pjungwir/floatvec/archive/master.zip && unzip master.zip && rm -rf master.zip && cd floatvec-master && make && make install

COPY --from=libsBuilder /usr/local/lib64/libCGAL.so.13 /usr/local/lib64/libCGAL.so.13
COPY --from=libsBuilder	/gcc-5.2.0/gcc-temp/x86_64-unknown-linux-gnu/libstdc++-v3/src/.libs/libstdc++.so.6.0.21	/usr/local/lib64/libstdc++.so.6.0.21

COPY --from=pgroutingBuilder /usr/lib/postgresql/${PG_MAJOR}/lib/libpgrouting-${PGROUTING_MAJOR}.so /usr/pgsql-12/lib/libpgrouting-${PGROUTING_MAJOR}.so
COPY --from=pgroutingBuilder /usr/share/postgresql/${PG_MAJOR}/extension /usr/pgsql-12/share/extension

COPY --from=boost-builder /usr/local/lib/libboost_system.so.1.67.0 /usr/pgsql-12/lib/
COPY --from=boost-builder /usr/local/lib/libboost_chrono.so.1.67.0 /usr/pgsql-12/lib/
COPY --from=boost-builder /usr/local/lib/libboost_date_time.so.1.67.0 /usr/pgsql-12/lib/
COPY --from=boost-builder /usr/local/lib/libboost_atomic.so.1.67.0 /usr/pgsql-12/lib/
COPY --from=boost-builder /usr/local/lib/libboost_thread.so.1.67.0 /usr/pgsql-12/lib/


COPY --from=plv8 /usr/pgsql-12/lib/plv8-2.3.14.so /usr/pgsql-12/lib/plv8-2.3.14.so
COPY --from=plv8 /usr/pgsql-12/share/extension /usr/pgsql-12/share/extension
COPY --from=plv8 /usr/pgsql-12/lib/bitcode /usr/pgsql-12/lib/bitcode

RUN cp /usr/local/lib64/libCGAL.so.13 /usr/pgsql-12/lib/ \
	&& ldconfig /usr/local/lib64

USER 26