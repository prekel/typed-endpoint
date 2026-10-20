(** Typed HTTP endpoint declarations with a shared runtime and OpenAPI contract. *)

(** Re-exports shared codecs, schema constructors, and the backend-specialized
    DSL functor. Applications select a backend by applying [Make]. *)
include module type of Builder
