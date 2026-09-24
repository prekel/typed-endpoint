(lang dune 3.14)

(name typed-endpoint)

(version 0.1.1)

(generate_opam_files true)

(source
 (github prekel/typed-endpoint))

(authors "Vladislav Prekel")

(maintainers "Vladislav Prekel")

(license MIT)

(package
 (name typed-endpoint)
 (synopsis "Typed HTTP route declarations with OpenAPI generation")
 (description
  "A framework-agnostic OCaml library for declaring typed HTTP routes and generating OpenAPI documents from the same definitions.")
 (depends
  (ocaml (>= 5.1.1))
  base
  yojson
  (ppx_let (>= v0.17.1))
  ppx_deriving_yojson
  (ppx_deriving_jsonschema (>= 0.0.8))
  (ocamlformat (and (= 0.29.0) :with-dev-setup))
  (ocaml-lsp-server :with-dev-setup))
 (tags
  (http routing openapi)))

(package
 (name typed-endpoint-opium)
 (synopsis "Opium integration for typed-endpoint")
 (description
  "An Opium backend that turns typed-endpoint declarations into an Opium application.")
 (depends
  (ocaml (>= 5.1.1))
  (typed-endpoint (= :version))
  (typed-endpoint-testing (and (= :version) :with-test))
  base
  cohttp
  lwt
  (opium (= 0.18.0))
  uri
  yojson
  (ppx_let (>= v0.17.1))
  (ppx_deriving_yojson :with-test)
  (ppx_deriving_jsonschema (and (>= 0.0.8) :with-test))
  (ppx_expect :with-test))
 (tags
  (http routing openapi opium)))

(package
 (name typed-endpoint-testing)
 (synopsis "In-memory testing backend for typed-endpoint")
 (description
  "A framework-free in-memory backend for testing typed-endpoint applications and examples.")
 (depends
  (ocaml (>= 5.1.1))
  (typed-endpoint (= :version))
  base
  uri
  yojson
  (jsonschema (and (>= 0.1.0) :with-test))
  (qcheck :with-test)
  (ppx_let (>= v0.17.1))
  (ppx_deriving_yojson :with-test)
  (ppx_deriving_jsonschema (and (>= 0.0.8) :with-test))
  (ocamlfind :with-test)
  (ppx_expect :with-test))
 (tags
  (http routing openapi testing)))

(package
 (name typed-endpoint-dream)
 (synopsis "Dream integration for typed-endpoint")
 (description
  "A Dream backend that turns typed-endpoint declarations into a Dream router.")
 (depends
  (ocaml (>= 5.1.1))
  (typed-endpoint (= :version))
  (typed-endpoint-testing (and (= :version) :with-test))
  base
  (dream (= 1.0.0~alpha8))
  lwt
  (ppx_let (>= v0.17.1))
  yojson)
 (tags
  (http routing openapi dream)))

(package
 (name typed-endpoint-eio)
 (synopsis "Native Eio integration for typed-endpoint")
 (description
  "A native cohttp-eio backend with routing for typed-endpoint declarations.")
 (depends
  (ocaml (>= 5.1.1))
  (typed-endpoint (= :version))
  (typed-endpoint-testing (and (= :version) :with-test))
  base
  (cohttp-eio (= 6.3.0))
  (eio (>= 1.2))
  http
  uri
  yojson)
 (tags
  (http routing openapi eio)))
