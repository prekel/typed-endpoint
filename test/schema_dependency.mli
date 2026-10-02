open! Base

(** Recursive schema used by tests that import definitions across compilation units. *)
type node =
  { value : int
  ; next : node option
  }
[@@deriving jsonschema]
