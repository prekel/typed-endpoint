all: build

PACKAGES = ./typed-endpoint.opam ./typed-endpoint-opium.opam \
	./typed-endpoint-dream.opam ./typed-endpoint-eio.opam \
	./typed-endpoint-testing.opam

.PHONY: create_switch
create_switch:
	opam switch create . 5.5.0 --no-install -y

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
	opam exec -- dune build --only-packages typed-endpoint,typed-endpoint-testing @install @runtest
	opam exec -- dune build --only-packages typed-endpoint,typed-endpoint-testing,typed-endpoint-opium @install @runtest
	opam exec -- dune build --only-packages typed-endpoint,typed-endpoint-testing,typed-endpoint-dream @install @runtest
	opam exec -- dune build --only-packages typed-endpoint,typed-endpoint-testing,typed-endpoint-eio @install @runtest

.PHONY: check
check: fmt build test doc package

.PHONY: clean
clean:
	opam exec -- dune clean --root .
