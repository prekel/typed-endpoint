all: build

PACKAGES = ./typed-endpoint.opam ./typed-endpoint-opium.opam \
	./typed-endpoint-dream.opam ./typed-endpoint-eio.opam

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

.PHONY: clean
clean:
	opam exec -- dune clean --root .
