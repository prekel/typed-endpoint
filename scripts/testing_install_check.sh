#!/usr/bin/env bash

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/typed-endpoint-testing-install.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
switch="$(opam switch show)"
source_dir="$work_dir/source"
prefix="$work_dir/install"
mkdir -p "$source_dir"

git ls-files --cached --others --exclude-standard -z \
  | while IFS= read -r -d '' source_path; do
      if [[ -e "$source_path" || -L "$source_path" ]]; then
        printf '%s\0' "$source_path"
      fi
    done \
  | tar --create --null --files-from - \
  | tar --extract --directory "$source_dir"

export PATH="$prefix/bin:$PATH"
export OCAMLPATH="$prefix/lib${OCAMLPATH:+:$OCAMLPATH}"

run_dune() {
  (cd "$source_dir" && opam exec --switch "$switch" -- dune "$@")
}

run_dune build -p typed-endpoint @install
run_dune install --prefix "$prefix" typed-endpoint

run_dune build -p typed-endpoint-testing @install
run_dune install --prefix "$prefix" typed-endpoint-testing

run_dune build -p typed-endpoint-ppx @install
run_dune install --prefix "$prefix" typed-endpoint-ppx

run_dune build -p typed-endpoint-openapi @install
run_dune install --prefix "$prefix" typed-endpoint-openapi
run_dune build -p typed-endpoint-openapi @runtest

run_dune build -p typed-endpoint-testing @install @runtest
OCAMLPATH="$prefix/lib" opam exec --switch "$switch" -- dune build \
  --root "$source_dir/release-smoke/typed-endpoint" @all

OCAMLPATH="$prefix/lib" opam exec --switch "$switch" -- dune build \
  --root "$source_dir/release-smoke/typed-endpoint-openapi" @all

printf 'typed-endpoint-testing isolated installation check passed\n'
