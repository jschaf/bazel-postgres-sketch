# This Docker files builds Postgres and bundles it as a tar.gz archive in
# the /work/out directory. The tar.gz archive contains all shared libraries
# necessary to run the included Postgres binaries as long as LD_LIBRARY_PATH
# is set.
FROM ubuntu:16.04

ARG PG_VERSION='13.3'
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y build-essential libreadline-dev zlib1g-dev flex bison \
                        libxml2-dev libxslt-dev libssl-dev libssl1.0.0 \
                        libxml2-utils xsltproc curl less git

ARG pg_src_dir='/work/postgres-src'
ARG dist_dir='/work/dist'
ARG out_dir='/work/out'


# Grab Postgres source code.
RUN mkdir -p "$pg_src_dir" \
  && curl --silent --location --show-error --fail \
         "https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2" \
         --output "/work/postgres-src.tar.bz2" \
  && tar xf '/work/postgres-src.tar.bz2' --strip-components 1 --directory "$pg_src_dir"


# Build Postgres
# ==============

# Apply custom patches to allow running initdb and postgres binaries as root.
# Normally, running Postgres as root is a bad idea but we'll be running postgres
# in Docker and setting up another user is a pain in the ass.
WORKDIR $pg_src_dir
COPY allow_root.patch /work
RUN git apply /work/allow_root.patch

# Postgres configure.
RUN mkdir -p $dist_dir $out_dir \
  && ./configure \
         --with-openssl \
         --with-zlib \
         --prefix=$out_dir
#         --with-libraries=/usr/include/openssl \
#         CFLAGS='-fPIC' \
#         LDFLAGS=-static

# Postgres install.
RUN make -j$(nproc) world
RUN make install-world

# Archive extra shared libraries.
RUN cp \
    /lib/x86_64-linux-gnu/libssl.so* \
    /usr/lib/x86_64-linux-gnu/libssl.so* \
    /lib/x86_64-linux-gnu/libcrypto.so* \
    /usr/lib/x86_64-linux-gnu/libcrypto.so* \
    $out_dir/lib

RUN cd $out_dir \
  && tar -czf /work/postgres-linux-amd64-files.tar.gz ./* \
  && chown 1000 /work/postgres-linux-amd64-files.tar.gz
