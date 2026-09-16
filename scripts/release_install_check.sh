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

if [ ! -f "$archive" ]; then
  printf 'release archive not found: %s\n' "$archive" >&2
  exit 66
fi

compiler="$(opam exec -- ocamlc -version)"
if [ "$compiler" != '5.5.1' ]; then
  printf 'OCaml 5.5.1 is required; active compiler is %s\n' "$compiler" >&2
  exit 65
fi

work_dir="$(mktemp -d "$release_dir/install-check.XXXXXX")"
source_dir="$work_dir/$prefix"
tar --extract --gzip --file "$archive" --directory "$work_dir"

opam exec -- dune build --root "$source_dir" @all @runtest @doc @install

for package in \
  typed-endpoint \
  typed-endpoint-opium \
  typed-endpoint-dream \
  typed-endpoint-eio; do
  opam exec -- dune build --root "$source_dir/release-smoke/$package" @all
done

printf 'OCaml 5.5.1 installation check passed: %s\n' "$work_dir"
