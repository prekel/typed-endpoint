#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
  printf 'usage: %s VERSION RELEASE_DIR\n' "$0" >&2
  exit 64
fi

version="$1"
release_dir="$2"
prefix="typed-endpoint-$version"
archive="$release_dir/$prefix.tar.gz"
checksum="$archive.sha256"
opam_dir="$release_dir/opam-repository"

mkdir -p "$release_dir"
git diff --check
git ls-files --cached --others --exclude-standard -z \
  | LC_ALL=C sort -z \
  | tar \
      --create \
      --gzip \
      --file "$archive" \
      --null \
      --files-from - \
      --transform "s,^,$prefix/,"
sha256sum "$archive" > "$checksum"
archive_sha256="$(awk '{ print $1 }' "$checksum")"

for package in \
  typed-endpoint \
  typed-endpoint-ppx \
  typed-endpoint-testing \
  typed-endpoint-opium \
  typed-endpoint-dream \
  typed-endpoint-eio; do
  package_dir="$opam_dir/packages/$package/$package.$version"
  mkdir -p "$package_dir"
  cp "$package.opam" "$package_dir/opam"
  printf '%s\n' \
    "archive: \"https://github.com/prekel/typed-endpoint/releases/download/v$version/$prefix.tar.gz\"" \
    'checksum: [' \
    "  \"sha256=$archive_sha256\"" \
    ']' \
    > "$package_dir/url"
done

printf 'created %s\n' "$archive"
printf 'created %s\n' "$checksum"
printf 'created %s\n' "$opam_dir"
