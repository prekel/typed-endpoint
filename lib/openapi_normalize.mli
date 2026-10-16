open! Base

(** Normalizes renderer output for human-readable OpenAPI without changing source
    schemas. Nested copies of registered object schemas reuse their names;
    anonymous primitives and collections remain inline. Response Objects stay
    inline. Identical path parameters shared by every operation are lifted to
    the Path Item; redundant operation descriptions are omitted. Only known
    schema positions are visited, preserving resources and reference scopes. *)
val document : Yojson.Safe.t -> Yojson.Safe.t
