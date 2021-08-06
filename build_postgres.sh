#!/usr/bin/env bash

# This script builds a Postgres tar.gz file that, once extracted, can run
# standalone on a Linux amd64 system with no pre-installed dependencies (like
# a Bazel remote build execution instance). The Postgres tar.gz file bundles
# shared libraries like OpenSSL and relies on you to set the LD_LIBRARY_PATH
# to <extracted_dir>/lib. See the "Running tests" section below for an example.
#
# Flags
#
# --debug  drop into a bash shell in the build container and test container;
#          skips uploading image to GCP storage. To continue after dropping
#          into bash, use 'exit'. You'll need to do it twice.
# --test   skip uploading and only runs tests

set -euo pipefail

script_dir="$(
  cd "$(dirname "$0")"
  pwd -P
)"

should_debug='no'
debug_cmd='true'
if [[ "$*" == *--debug* ]]; then
  should_debug='yes'
  # If run with --debug, drop into a bash shell after building.
  debug_cmd='bash'
fi

should_test='no'
if [[ "$*" == *--test* ]]; then
  should_test='yes'
fi

echo "
Building Postgres
=================
"
# Make rm work even if no glob in zsh, https://superuser.com/a/1607656
{ rm -f "$script_dir/test/"*.tar.gz; } 2>/dev/null || true
# Use buildx to always build for Linux amd64.
docker buildx build -t third_party_postgres --platform=linux/amd64 "$script_dir"
docker run -it --rm \
  --platform=linux/amd64 \
  --mount "type=bind,src=$script_dir/test,dst=/work/dist" \
  --workdir='/work/out' \
  third_party_postgres \
  sh -c "$debug_cmd && mv -f /work/postgres-linux-amd64-files.tar.gz /work/dist/"

echo "
Running tests
=============
"
# Use buildx to always build for Linux amd64.
docker buildx build -t third_party_postgres_test --platform=linux/amd64 "$script_dir/test"
docker run -it --rm \
  --platform=linux/amd64 \
  --env LD_LIBRARY_PATH=/work/lib \
  third_party_postgres_test \
  sh -c "$debug_cmd && /work/bin/initdb /pgdata"

if [[ $should_debug == 'yes' ]]; then
  echo
  echo 'Skipping upload because of --debug flag'
  exit 0
fi

if [[ $should_test == 'yes' ]]; then
  echo
  echo 'Skipping upload because of --test flag'
  exit 0
fi

echo "
Uploading archive
=================
"
archive="$script_dir/test/postgres-linux-amd64-files.tar.gz"
sha256="$(shasum -a 256 < "$archive" | awk '{ print $1 }')"
short_sha="$(echo "$sha256" | cut -c 1-8)"
postgres_tar="$script_dir/test/postgres13.3_linux_am64_files.$short_sha.tar.gz"
mv -f "$archive" "$postgres_tar"
dest_file="TODO_REPLACE_ME/postgres/$(basename "$postgres_tar")"
gsutil cp "$postgres_tar" "gs://$dest_file"

echo "
Printing Bazel repo rule
========================

Update //third_party/postgres/repo.bzl with:

    http_archive(
        name = \"postgres_linux_amd64_files\",
        build_file_content = all_files,
        urls = [
            \"https://storage.googleapis.com/$dest_file\",
        ],
        sha256 = \"$sha256\",
    )
"
