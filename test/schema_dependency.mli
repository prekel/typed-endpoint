(** Cross-compilation-unit fixture for recursive schema derivation. The
    generated [node_jsonschema] must preserve recursive definitions when another
    DTO embeds this type. *)

open! Base

(** Recursive schema used by tests that import definitions across compilation units. *)
type node =
  { value : int
  ; next : node option
  }
[@@deriving jsonschema]
