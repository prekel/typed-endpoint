all: build

PACKAGES = ./typed-endpoint.opam ./typed-endpoint-ppx.opam ./typed-endpoint-opium.opam \
	./typed-endpoint-dream.opam ./typed-endpoint-eio.opam \
	./typed-endpoint-testing.opam

RELEASE_VERSION = 0.2.0
RELEASE_DIR = _release

.PHONY: create_switch
create_switch:
	opam switch create . 5.1.1 --no-install -y

.PHONY: deps
deps:
	opam install --deps-only $(PACKAGES) -y

.PHONY: deps_all
deps_all:
	opam install --deps-only --with-test --with-doc --with-dev-setup $(PACKAGES) -y

.PHONY: build
build:
	opam exec -- dune build --root . @all

.PHONY: test
test:
	opam exec -- dune runtest --root .

.PHONY: fmt
fmt:
	opam exec -- dune build --root . @fmt

.PHONY: doc
doc:
	opam exec -- dune build --root . @doc

.PHONY: package
package: smoke
	opam exec -- dune build --root . @install
	opam lint $(PACKAGES)

.PHONY: smoke
smoke:
	opam exec -- dune build -p typed-endpoint @install @runtest
	opam exec -- dune build --only-packages typed-endpoint,typed-endpoint-ppx @install @runtest
	opam exec -- dune build --only-packages typed-endpoint,typed-endpoint-testing @install @runtest
	opam exec -- dune build --only-packages typed-endpoint,typed-endpoint-testing,typed-endpoint-opium @install @runtest
	opam exec -- dune build --only-packages typed-endpoint,typed-endpoint-testing,typed-endpoint-dream @install @runtest
	opam exec -- dune build --only-packages typed-endpoint,typed-endpoint-testing,typed-endpoint-eio @install @runtest

.PHONY: check
check: fmt build test doc package

.PHONY: release-check
release-check: check
	git diff --check

.PHONY: release-artifacts
release-artifacts:
	./scripts/release_archive.sh $(RELEASE_VERSION) $(RELEASE_DIR)

.PHONY: release-install-check
release-install-check: release-artifacts
	./scripts/release_install_check.sh $(RELEASE_VERSION) $(RELEASE_DIR)

.PHONY: clean
clean:
	opam exec -- dune clean --root .
