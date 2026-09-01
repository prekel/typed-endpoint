(lang dune 3.14)

(name typed-endpoint)

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
  (ocaml (>= 4.14.1))
  dune
  base
  lwt
  yojson
  (lwt_ppx :build)
  (ppx_deriving_yojson :build)
  (ppx_deriving_jsonschema :build)
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
  (ocaml (>= 4.14.1))
  dune
  (typed-endpoint (= :version))
  base
  cohttp
  lwt
  (opium (= 0.18.0))
  uri
  yojson
  (lwt_ppx :with-test)
  (ppx_deriving_yojson :with-test)
  (ppx_deriving_jsonschema :with-test)
  (ppx_expect :with-test))
 (tags
  (http routing openapi opium)))
