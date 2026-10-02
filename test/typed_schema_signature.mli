open! Base
open Typed_endpoint

(** Generic DTO shape used to check the type index of generated schemas. *)
type 'a t = { value : 'a } [@@deriving jsonschema]

(** Schema specialization for integer payloads. *)
val int_schema : int t Json_schema.t
